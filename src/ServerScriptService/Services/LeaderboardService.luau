--!nonstrict
-- ServerScriptService/Services/LeaderboardService.luau
-- 3 GLOBALNE leaderboardy na fizycznych tablicach (Workspace.Top.*.Leaderboard, SurfaceGui z List+Template),
-- przejete z innej gry i przestrojone pod WAR RNG. Kategorie (lewo->prawo po X): TOP WAVES / TOP COINS / TOP ROLLS.
-- Zrodlo: OrderedDataStore (globalne, miedzy-serwerowe) + nakladka LIVE graczy z tego serwera. Gdy DataStore
-- niedostepny (Studio bez API access) -> fallback: sam bieżący serwer. Serwer wypelnia tablice (replikuja do wszystkich).
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

local LeaderboardService = {}

local TOP_N = 25
local WRITE_EVERY = 45 -- s: zrzut statow online graczy do OrderedDataStore
local READ_EVERY = 60 -- s: odczyt topN + odswiezenie tablic

local RANK_COLORS = { -- top3 = zloto/srebro/braz, reszta bialy
	Color3.fromRGB(255, 210, 40),
	Color3.fromRGB(205, 214, 224),
	Color3.fromRGB(214, 140, 66),
}

local function fmtShort(n)
	n = math.floor((tonumber(n) or 0) + 0.5)
	if n >= 1e12 then return string.format("%.1fT", n / 1e12) end
	if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(n)
end
local function fmtInt(n)
	-- grupowanie przecinkami (fale to male liczby, ale np. rekordowe moga rosnac)
	local s = tostring(math.floor((tonumber(n) or 0) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- kategorie (kolejnosc = przypisanie do tablic sortowanych po X rosnaco)
local CATS = {
	{ id = "waves", store = "LB_v1_bestWave", title = "TOP WAVES", stat = function(d) return d.bestWave or 0 end, fmt = fmtInt },
	{ id = "coins", store = "LB_v1_coins", title = "TOP COINS", stat = function(d) return d.coins or 0 end, fmt = fmtShort },
	{ id = "rolls", store = "LB_v1_rolls", title = "TOP ROLLS", stat = function(d) return d.lifetimeRolls or 0 end, fmt = fmtShort },
}

local _profile
local _boards = {} -- [catId] = { list, tmpl, title }
local _stores = {} -- [catId] = OrderedDataStore
local _nameCache = {} -- userId -> name
local _thumbCache = {} -- userId -> content
local _lastWrite = {} -- userId -> { [catId] = value } (throttle SetAsync)

-- ── resolve nick + avatar (cache; pcall bo web-call) ──────────────────────────
local function resolveName(userId, online)
	if online and online.Name then _nameCache[userId] = online.Name end
	if _nameCache[userId] then return _nameCache[userId] end
	local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	name = (ok and name) or ("Player" .. userId)
	_nameCache[userId] = name
	return name
end
local function resolveThumb(userId)
	if _thumbCache[userId] then return _thumbCache[userId] end
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	content = (ok and content) or ""
	if content ~= "" then _thumbCache[userId] = content end
	return content
end

-- ── zebranie topN dla kategorii: OrderedDataStore + nakladka LIVE ─────────────
local function gatherTop(cat)
	local merged = {} -- userId(number) -> value
	-- globalne z OrderedDataStore
	local store = _stores[cat.id]
	if store then
		local ok, pages = pcall(function() return store:GetSortedAsync(false, TOP_N) end)
		if ok and pages then
			local okp, page = pcall(function() return pages:GetCurrentPage() end)
			if okp and page then
				for _, item in ipairs(page) do
					local uid = tonumber(item.key)
					if uid then merged[uid] = math.max(merged[uid] or 0, item.value) end
				end
			end
		end
	end
	-- nakladka LIVE (aktualni gracze — najswiezsze wartosci, tez gdy DataStore off)
	for _, plr in ipairs(Players:GetPlayers()) do
		local data = _profile.GetProfile(plr)
		if data then
			local v = cat.stat(data)
			merged[plr.UserId] = math.max(merged[plr.UserId] or 0, v)
		end
	end
	-- sortuj malejaco
	local list = {}
	for uid, v in pairs(merged) do list[#list + 1] = { userId = uid, value = v } end
	table.sort(list, function(a, b) return a.value > b.value end)
	while #list > TOP_N do table.remove(list) end
	return list
end

-- ── wypelnij fizyczna tablice ────────────────────────────────────────────────
local function populate(cat, entries)
	local b = _boards[cat.id]
	if not b then return end
	if b.title then b.title.Text = cat.title end
	b.tmpl.Visible = false
	-- usun stare wiersze
	for _, c in ipairs(b.list:GetChildren()) do
		if c:GetAttribute("WR_LBRow") then c:Destroy() end
	end
	local onlineByUid = {}
	for _, plr in ipairs(Players:GetPlayers()) do onlineByUid[plr.UserId] = plr end
	for i, e in ipairs(entries) do
		local row = b.tmpl:Clone()
		row.Name = "Row" .. i
		row:SetAttribute("WR_LBRow", true)
		row.Visible = true
		row.LayoutOrder = i
		local rank = row:FindFirstChild("Rank")
		if rank then
			rank.Text = "#" .. i
			rank.TextColor3 = RANK_COLORS[i] or Color3.new(1, 1, 1)
		end
		local uname = row:FindFirstChild("Username")
		if uname then uname.Text = resolveName(e.userId, onlineByUid[e.userId]) end
		local img = row:FindFirstChild("PlayerImage")
		if img then
			local t = resolveThumb(e.userId)
			if t ~= "" then img.Image = t end
		end
		local valFrame = row:FindFirstChild("Value")
		local val = valFrame and valFrame:FindFirstChild("Value")
		if val then val.Text = cat.fmt(e.value) end
		row.Parent = b.list
	end
end

-- ── zrzut statow online graczy do OrderedDataStore (throttle) ─────────────────
local function writePlayer(plr)
	local data = _profile.GetProfile(plr)
	if not data then return end
	local last = _lastWrite[plr.UserId]
	if not last then last = {}; _lastWrite[plr.UserId] = last end
	for _, cat in ipairs(CATS) do
		local store = _stores[cat.id]
		if store then
			local v = math.floor(cat.stat(data) + 0.5)
			if v > 0 and last[cat.id] ~= v then
				local ok = pcall(function() store:SetAsync(plr.UserId, v) end)
				if ok then last[cat.id] = v end
			end
		end
	end
end

-- ── podepnij fizyczne tablice (Workspace.Top.*.Leaderboard) po X rosnaco ──────
local function bindBoards()
	local found = {}
	for _, m in ipairs(workspace:GetChildren()) do
		if m.Name == "Top" and m:IsA("Model") then
			local lb = m:FindFirstChild("Leaderboard")
			local surf = lb and lb:FindFirstChildOfClass("SurfaceGui")
			local list = surf and surf:FindFirstChild("List")
			local tmpl = list and list:FindFirstChild("Template")
			if lb and list and tmpl then
				local title
				for _, d in ipairs(surf:GetDescendants()) do
					if d:IsA("TextLabel") and d ~= tmpl and not d:IsDescendantOf(tmpl) and d.Parent == list then
						title = d
						break
					end
				end
				found[#found + 1] = { x = lb.Position.X, list = list, tmpl = tmpl, title = title }
			end
		end
	end
	table.sort(found, function(a, b) return a.x < b.x end)
	for i, cat in ipairs(CATS) do
		local b = found[i]
		if b then _boards[cat.id] = { list = b.list, tmpl = b.tmpl, title = b.title } end
	end
end

-- ── boot ──────────────────────────────────────────────────────────────────────
function LeaderboardService.Init() end

function LeaderboardService.Start()
	_profile = require(Services:WaitForChild("ProfileService"))
	for _, cat in ipairs(CATS) do
		local ok, s = pcall(function() return DataStoreService:GetOrderedDataStore(cat.store) end)
		_stores[cat.id] = ok and s or nil
	end
	bindBoards()

	-- gracz wychodzi -> natychmiastowy zrzut jego statow
	_profile.ProfileReleasing:Connect(function(player)
		writePlayer(player)
	end)

	-- petla ZAPISU
	task.spawn(function()
		while true do
			task.wait(WRITE_EVERY)
			for _, plr in ipairs(Players:GetPlayers()) do
				writePlayer(plr)
			end
		end
	end)
	-- petla ODCZYTU + odswiezenie tablic (pierwszy raz od razu)
	task.spawn(function()
		while true do
			for _, cat in ipairs(CATS) do
				local entries = gatherTop(cat)
				populate(cat, entries)
			end
			task.wait(READ_EVERY)
		end
	end)
end

-- hook testowy: wymus odswiezenie wszystkich tablic teraz
function LeaderboardService.RefreshNow()
	for _, cat in ipairs(CATS) do
		populate(cat, gatherTop(cat))
	end
end

return LeaderboardService
