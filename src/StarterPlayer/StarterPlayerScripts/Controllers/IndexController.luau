--!nonstrict
-- StarterPlayerScripts/Controllers/IndexController.luau  (ETAP 2 — klient, model wzorca)
-- 4 zakladki (Regularny / Blyszczacy / Galaktyka / Wrogowie), siatka slotow z ramka rzadkosci,
-- panel detali (staty EFEKTYWNE wg poziomu + POZIOM + przycisk Ulepsz), dolny pasek bonusu luck.
-- Wrogowie = STUB (sloty puste, tresc etap 5). Stan: GetIndexState (RF; discovered per-wariant + levels +
-- luck) na otwarcie; IndexUpdated (S->C) live (nowy wpis per-wariant + %/luck). Ulepsz -> LevelUpUnit RF
-- (server-auth spend, Etap 3). ODBIERZ bonus luck per prog (Etap 4, ClaimIndexLuck RF). Bestiariusz = etap 5.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)
local HudOverlay = require(script.Parent:WaitForChild("HudOverlay"))

local IndexController = {}

-- ── stan ──────────────────────────────────────────────────────────────────────
local _catsById = {} -- id -> {id,label,kind,variant,discovered={uid=true},count,total,percent}
local _catOrder = {} -- lista id w kolejnosci zakladek
local _overall = { count = 0, total = 0, percent = 0 }
local _luckBonus = 0
local _activeCat = nil
local _unitOrder = {} -- unitId po rarityN rosnaco (stabilne)
local _levels = {} -- unitId -> poziom (z GetIndexState; update po LevelUpUnit) — ETAP 3
local _coins = 0 -- saldo (CoinsSync) do koloru przycisku Ulepsz (stac/nie stac)
local _claimed = {} -- {[pct]=true} odebrane progi bonusu luck (ETAP 4)
local _claimBtns = {} -- pct -> TextButton ODBIERZ
local _panel, _grid, _luckLabel, _toast, _tabBtns = nil, nil, nil, nil, {}
local _detail = {} -- {frame, name, rarity, stats, level, upBtn, selUnit, selVariant}

local NL = string.char(10) -- newline (bez sekwencji escape w zrodle — MCP sync je psul)

-- 2.9K / 1.2M
local function fmtNum(n)
	n = n or 0
	if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n + 0.5))
end

-- koszt WYSWIETLANY (mirror LevelService.GetCost): floor(floor(rarityN*baseCostK) * costGrowth^level)
local function costOf(unitId, level)
	local u = GameConfig.Units[unitId]
	local base = math.floor(((u and u.rarityN) or 1) * GameConfig.Level.baseCostK)
	return math.floor(base * (GameConfig.Level.costGrowth ^ level))
end

-- ── rzadkosc / warianty (prezentacja) ───────────────────────────────────────────
local TIER_COLOR = {
	[1] = Color3.fromRGB(150, 150, 160), -- Common
	[2] = Color3.fromRGB(90, 190, 110), -- Uncommon
	[3] = Color3.fromRGB(80, 140, 230), -- Rare
	[4] = Color3.fromRGB(170, 90, 220), -- Epic
	[5] = Color3.fromRGB(240, 180, 60), -- Legendary
}
local VARIANT_BADGE = { shiny = "✨", galaxy = "🌌" }
local VARIANT_TINT = { shiny = Color3.fromRGB(255, 240, 150), galaxy = Color3.fromRGB(170, 140, 255) }

local function tierFor(rarityN)
	for _, t in ipairs(GameConfig.Rarity.tiers) do
		if rarityN <= t.maxN then
			return t
		end
	end
	return GameConfig.Rarity.tiers[#GameConfig.Rarity.tiers]
end

local function mkLabel(parent, size, pos, text, size2, color)
	local l = Instance.new("TextLabel")
	l.Size = size; l.Position = pos; l.BackgroundTransparency = 1
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Font = Enum.Font.Gotham; l.TextSize = size2 or 14; l.Text = text; l.Parent = parent
	return l
end

-- ── panel detali (ETAP 3: staty EFEKTYWNE wg poziomu + poziom + przycisk Ulepsz przez LevelUpUnit) ──────
-- Odswiez sam przycisk Ulepsz (tekst/kolor) wg poziomu i salda.
local function refreshUpgradeBtn(unitId)
	if not _detail.upBtn then return end
	local level = _levels[unitId] or 0
	if level >= GameConfig.Level.maxLevel then
		_detail.upBtn.Text = "Poziom MAX"
		_detail.upBtn.BackgroundColor3 = Color3.fromRGB(70, 74, 86)
	else
		local cost = costOf(unitId, level)
		_detail.upBtn.Text = "Ulepsz — " .. fmtNum(cost) .. " monet"
		_detail.upBtn.BackgroundColor3 = (_coins >= cost) and Color3.fromRGB(80, 165, 95) or Color3.fromRGB(150, 70, 70)
	end
	_detail.upBtn.Visible = true
end

local function showDetail(unitId, variant)
	local u = GameConfig.Units[unitId]
	if not u then
		return
	end
	_detail.selUnit, _detail.selVariant = unitId, variant
	local tier = tierFor(u.rarityN)
	local level = _levels[unitId] or 0
	local mult = GameConfig.Level.growthPerLevel ^ level -- level TYPU (wariant-niezalezny)
	_detail.name.Text = (u.displayName or unitId) .. (VARIANT_BADGE[variant] and (" " .. VARIANT_BADGE[variant]) or "")
	_detail.name.TextColor3 = VARIANT_TINT[variant] or Color3.new(1, 1, 1)
	_detail.rarity.Text = ("Rzadkosc: %s (1 in %d)"):format(tier.name, u.rarityN)
	_detail.rarity.TextColor3 = TIER_COLOR[tier.revealTier]
	if u.combat then -- WEAPON: level buffuje dmg (fireRate/range bez zmian)
		local c = u.combat
		local effRange = c.range and math.floor(c.range * (GameConfig.Sim.unitRangeMult or 1) + 0.5) or "-"
		local effDmg = math.floor((c.dmg or 0) * mult + 0.5)
		_detail.stats.Text = "Obrazenia: " .. effDmg .. NL
			.. "Szybkostrzelnosc: " .. tostring(c.fireRate or "-") .. "/s" .. NL
			.. "Zasieg: " .. tostring(effRange)
	else -- BLOCK: level buffuje HP
		local effHp = math.floor((u.hp or 0) * mult + 0.5)
		local defTxt = u.def and (NL .. "Pancerz (DEF): " .. u.def) or ""
		_detail.stats.Text = "HP: " .. effHp .. defTxt
	end
	_detail.level.Text = "Poziom: " .. level
	_detail.level.Visible = true
	refreshUpgradeBtn(unitId)
end

local function clearDetail()
	_detail.name.Text = "Wybierz odkryty wpis"
	_detail.name.TextColor3 = Color3.fromRGB(150, 150, 160)
	_detail.rarity.Text = ""
	_detail.stats.Text = ""
	_detail.selUnit, _detail.selVariant = nil, nil
	if _detail.level then _detail.level.Visible = false end
	if _detail.upBtn then _detail.upBtn.Visible = false end
end

-- ── siatka slotow aktywnej kategorii ────────────────────────────────────────────
local function clearGrid()
	for _, ch in ipairs(_grid:GetChildren()) do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
end

local function mkSlot(i, cols, cw, ch, gap, borderColor, dim)
	local col = (i - 1) % cols
	local row = math.floor((i - 1) / cols)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(cw, ch)
	frame.Position = UDim2.fromOffset(col * (cw + gap), row * (ch + gap))
	frame.BackgroundColor3 = dim and Color3.fromRGB(28, 28, 36) or Color3.fromRGB(44, 44, 56)
	frame.BorderSizePixel = 0; frame.Parent = _grid
	local stroke = Instance.new("UIStroke")
	stroke.Color = borderColor; stroke.Thickness = 2; stroke.Parent = frame
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 6); corner.Parent = frame
	return frame
end

local function renderUnitCategory(cat)
	local cols, cw, ch, gap = 3, 100, 72, 8
	for i, unitId in ipairs(_unitOrder) do
		local u = GameConfig.Units[unitId]
		local tier = tierFor(u.rarityN)
		local border = TIER_COLOR[tier.revealTier]
		local discovered = cat.discovered[unitId] == true
		local frame = mkSlot(i, cols, cw, ch, gap, border, not discovered)
		if discovered then
			local nameLbl = mkLabel(frame, UDim2.new(1, -6, 1, -6), UDim2.fromOffset(3, 3),
				(u.displayName or unitId), 12)
			nameLbl.TextWrapped = true; nameLbl.TextYAlignment = Enum.TextYAlignment.Center
			nameLbl.TextXAlignment = Enum.TextXAlignment.Center
			local badge = VARIANT_BADGE[cat.variant]
			if badge then
				local b = mkLabel(frame, UDim2.fromOffset(20, 20), UDim2.new(1, -22, 0, 2), badge, 14,
					VARIANT_TINT[cat.variant])
				b.ZIndex = 3
			end
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.fromScale(1, 1); btn.BackgroundTransparency = 1; btn.Text = ""
			btn.ZIndex = 4; btn.Parent = frame
			btn.MouseButton1Click:Connect(function() showDetail(unitId, cat.variant) end)
		else
			local q = mkLabel(frame, UDim2.fromScale(1, 1), UDim2.new(), "?", 22,
				Color3.fromRGB(110, 110, 122))
			q.TextXAlignment = Enum.TextXAlignment.Center
		end
	end
	_grid.CanvasSize = UDim2.fromOffset(0, math.ceil(#_unitOrder / 3) * 80) -- 3 kolumny, wiersz 72+8
end

local function renderEnemyCategory(cat)
	-- STUB: sloty puste (tresc bestiariusza = etap 5)
	local cols, cw, ch, gap = 3, 100, 72, 8
	for i = 1, cat.total do
		local frame = mkSlot(i, cols, cw, ch, gap, Color3.fromRGB(90, 60, 60), true)
		local q = mkLabel(frame, UDim2.fromScale(1, 1), UDim2.new(), "?", 22, Color3.fromRGB(110, 90, 90))
		q.TextXAlignment = Enum.TextXAlignment.Center
	end
	local note = mkLabel(_grid, UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, math.ceil(cat.total / 3) * 80 + 8),
		"Bestiariusz wrogow — wkrotce (etap 5)", 13, Color3.fromRGB(200, 150, 150))
	note.TextXAlignment = Enum.TextXAlignment.Left
	_grid.CanvasSize = UDim2.fromOffset(0, math.ceil(cat.total / 3) * 80 + 52) -- + miejsce na notke
end

local function renderCategory(catId)
	_activeCat = catId
	clearGrid()
	clearDetail()
	for id, btn in pairs(_tabBtns) do
		btn.BackgroundColor3 = (id == catId) and Color3.fromRGB(70, 90, 120) or Color3.fromRGB(40, 40, 52)
	end
	local cat = _catsById[catId]
	if not cat then
		return
	end
	if cat.kind == "unit" then
		renderUnitCategory(cat)
	else
		renderEnemyCategory(cat)
	end
end

local function refreshLuck()
	if _luckLabel then
		_luckLabel.Text = ("Szczescie indeksu: +%.2f   (%d%%  %d/%d odkryte)"):format(
			_luckBonus, math.floor(_overall.percent + 0.5), _overall.count, _overall.total)
	end
end

-- ETAP 4: przyciski ODBIERZ per prog. claimed=✓(szary), reached&!claimed=ODBIERZ(zielony), inaczej=zablokowany.
local function renderClaims()
	local percent = _overall.percent or 0
	for _, t in ipairs(GameConfig.Index.luckThresholds) do
		local btn = _claimBtns[t.pct]
		if btn then
			if _claimed[t.pct] then
				btn.Text = ("✓ %d%%  +%.1f"):format(t.pct, t.luck)
				btn.BackgroundColor3 = Color3.fromRGB(55, 85, 60); btn.AutoButtonColor = false
			elseif percent >= t.pct then
				btn.Text = ("ODBIERZ  +%.1f"):format(t.luck)
				btn.BackgroundColor3 = Color3.fromRGB(80, 170, 90); btn.AutoButtonColor = true
			else
				btn.Text = ("%d%%  +%.1f"):format(t.pct, t.luck)
				btn.BackgroundColor3 = Color3.fromRGB(48, 48, 60); btn.AutoButtonColor = false
			end
		end
	end
end

local function applyState(state)
	_catsById = {}
	_catOrder = {}
	for _, c in ipairs(state.categories or {}) do
		c.discovered = c.discovered or {}
		_catsById[c.id] = c
		_catOrder[#_catOrder + 1] = c.id
	end
	_overall = state.overall or _overall
	_luckBonus = state.luckBonus or 0
	_levels = state.levels or {} -- poziomy typow (ETAP 3) do detail panelu
	_claimed = {}
	for _, t in ipairs(state.thresholds or {}) do -- ETAP 4: stan odebranych progow
		_claimed[t.pct] = t.claimed == true
	end
	refreshLuck()
	renderClaims()
	renderCategory(_activeCat or _catOrder[1])
end

local function showToast(unitId, variant)
	if not _toast then
		return
	end
	local u = GameConfig.Units[unitId]
	local badge = VARIANT_BADGE[variant]
	_toast.Text = "Nowy wpis: " .. ((u and u.displayName) or unitId) .. (badge and (" " .. badge) or "")
	_toast.Visible = true
	task.delay(2.5, function()
		if _toast then
			_toast.Visible = false
		end
	end)
end

local function closePanel()
	_panel.Visible = false
	HudOverlay.exit() -- przywroc HUD
end

local function openPanel()
	HudOverlay.enter(true) -- schowaj caly HUD, ZOSTAW monety (lewy gorny)
	_panel.Visible = true
	local state = Net.get("GetIndexState"):InvokeServer()
	if state then
		applyState(state)
	end
end

-- ── budowa statycznego UI ───────────────────────────────────────────────────────
function IndexController.start()
	-- kolejnosc jednostek: po rarityN rosnaco (stabilna prezentacja)
	_unitOrder = {}
	for id in pairs(GameConfig.Units) do
		_unitOrder[#_unitOrder + 1] = id
	end
	table.sort(_unitOrder, function(a, b)
		return GameConfig.Units[a].rarityN < GameConfig.Units[b].rarityN
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_Index"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 150 -- NAD HUD ziomka (SideButtons=100), pod modalem podsumowania (200)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- TYMCZASOWY przycisk wejscia (re-hook do HUD ksiazki gdy bedzie)
	-- HUD: lewa krawedz, wysrodkowany w pionie (slot nawigacji "Indeks" ze wzorca)
	local openBtn = Instance.new("TextButton")
	openBtn.Size = UDim2.fromOffset(120, 54); openBtn.AnchorPoint = Vector2.new(0, 0.5)
	openBtn.Position = UDim2.new(0, 16, 0.5, 6) -- lewa nawigacja, POD Sklepem (HudController)
	openBtn.BackgroundColor3 = Color3.fromRGB(90, 75, 40); openBtn.TextColor3 = Color3.new(1, 1, 1)
	openBtn.Font = Enum.Font.GothamBold; openBtn.TextSize = 16; openBtn.Text = "INDEKS"; openBtn.Parent = gui
	local ibCorner = Instance.new("UICorner"); ibCorner.CornerRadius = UDim.new(0, 10); ibCorner.Parent = openBtn

	_panel = Instance.new("Frame")
	_panel.Size = UDim2.fromOffset(660, 470); _panel.Position = UDim2.fromScale(0.5, 0.5)
	_panel.AnchorPoint = Vector2.new(0.5, 0.5)
	_panel.BackgroundColor3 = Color3.fromRGB(22, 22, 30); _panel.BorderSizePixel = 0
	_panel.Visible = false; _panel.Parent = gui
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 10); pc.Parent = _panel

	local title = mkLabel(_panel, UDim2.fromOffset(300, 26), UDim2.fromOffset(16, 10), "KOLEKCJA (INDEKS)", 18)
	title.Font = Enum.Font.GothamBold; title.TextXAlignment = Enum.TextXAlignment.Left

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(28, 28); closeBtn.Position = UDim2.new(1, -38, 0, 10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40); closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 16; closeBtn.Text = "X"; closeBtn.Parent = _panel
	closeBtn.MouseButton1Click:Connect(closePanel)

	-- lewa kolumna zakladek
	local tabCol = Instance.new("Frame")
	tabCol.Size = UDim2.fromOffset(130, 300); tabCol.Position = UDim2.fromOffset(16, 48)
	tabCol.BackgroundTransparency = 1; tabCol.Parent = _panel
	_tabBtns = {}

	-- srodkowa siatka (ScrollingFrame: 19+ typow nie miesci sie -> clip + pionowy scroll)
	_grid = Instance.new("ScrollingFrame")
	_grid.Name = "Grid"; _grid.Size = UDim2.fromOffset(330, 320); _grid.Position = UDim2.fromOffset(156, 48)
	_grid.BackgroundTransparency = 1; _grid.BorderSizePixel = 0
	_grid.ScrollBarThickness = 6; _grid.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 110)
	_grid.ScrollingDirection = Enum.ScrollingDirection.Y; _grid.CanvasSize = UDim2.new()
	_grid.Parent = _panel

	-- prawy panel detali
	local detailFrame = Instance.new("Frame")
	detailFrame.Size = UDim2.fromOffset(150, 320); detailFrame.Position = UDim2.fromOffset(494, 48)
	detailFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40); detailFrame.BorderSizePixel = 0
	detailFrame.Parent = _panel
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(0, 8); dc.Parent = detailFrame
	_detail.frame = detailFrame
	_detail.name = mkLabel(detailFrame, UDim2.new(1, -16, 0, 44), UDim2.fromOffset(8, 10), "", 15)
	_detail.name.Font = Enum.Font.GothamBold; _detail.name.TextWrapped = true
	_detail.name.TextXAlignment = Enum.TextXAlignment.Left; _detail.name.TextYAlignment = Enum.TextYAlignment.Top
	_detail.rarity = mkLabel(detailFrame, UDim2.new(1, -16, 0, 36), UDim2.fromOffset(8, 58), "", 12)
	_detail.rarity.TextWrapped = true; _detail.rarity.TextXAlignment = Enum.TextXAlignment.Left
	_detail.stats = mkLabel(detailFrame, UDim2.new(1, -16, 0, 96), UDim2.fromOffset(8, 100), "", 13,
		Color3.fromRGB(210, 210, 220))
	_detail.stats.TextXAlignment = Enum.TextXAlignment.Left; _detail.stats.TextYAlignment = Enum.TextYAlignment.Top

	-- ETAP 3: aktualny poziom + przycisk Ulepsz (dom tymczasowego przycisku lewelowania z Task A)
	_detail.level = mkLabel(detailFrame, UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 208), "", 14,
		Color3.fromRGB(255, 220, 120))
	_detail.level.Font = Enum.Font.GothamBold; _detail.level.TextXAlignment = Enum.TextXAlignment.Left
	_detail.level.Visible = false
	_detail.upBtn = Instance.new("TextButton")
	_detail.upBtn.Size = UDim2.new(1, -16, 0, 40); _detail.upBtn.Position = UDim2.fromOffset(8, 236)
	_detail.upBtn.BackgroundColor3 = Color3.fromRGB(80, 165, 95); _detail.upBtn.BorderSizePixel = 0
	_detail.upBtn.Font = Enum.Font.GothamBold; _detail.upBtn.TextSize = 13; _detail.upBtn.TextColor3 = Color3.new(1, 1, 1)
	_detail.upBtn.Text = "Ulepsz"; _detail.upBtn.AutoButtonColor = true; _detail.upBtn.Visible = false
	_detail.upBtn.Parent = detailFrame
	local ubc = Instance.new("UICorner"); ubc.CornerRadius = UDim.new(0, 8); ubc.Parent = _detail.upBtn
	-- klik -> LevelUpUnit RF (server-auth spend); po ok odswiez poziom + staty EFEKTYWNE + koszt nastepnego
	_detail.upBtn.MouseButton1Click:Connect(function()
		local unitId = _detail.selUnit
		if not unitId then return end
		local res = Net.get("LevelUpUnit"):InvokeServer(unitId)
		if type(res) == "table" and res.ok then
			_levels[unitId] = res.newLevel
			showDetail(unitId, _detail.selVariant)
		else
			local reason = type(res) == "table" and res.reason or "?"
			_detail.upBtn.Text = (reason == "NotEnoughCoins") and "Brak monet!"
				or (reason == "MaxLevel" and "Poziom MAX" or "Blad")
			task.delay(0.9, function()
				if _detail.selUnit == unitId then refreshUpgradeBtn(unitId) end
			end)
		end
	end)

	-- saldo monet (kolor przycisku Ulepsz: stac/nie stac)
	Net.get("CoinsSync").OnClientEvent:Connect(function(p)
		if type(p) == "table" and type(p.balance) == "number" then
			_coins = p.balance
			if _detail.selUnit then refreshUpgradeBtn(_detail.selUnit) end
		end
	end)

	-- dolny pasek: suma bonusu luck + przyciski ODBIERZ per prog (ETAP 4)
	_luckLabel = mkLabel(_panel, UDim2.new(1, -32, 0, 22), UDim2.new(0, 16, 1, -92),
		"Szczescie indeksu: +0.00", 15, Color3.fromRGB(255, 220, 120))
	_luckLabel.Font = Enum.Font.GothamBold; _luckLabel.TextXAlignment = Enum.TextXAlignment.Left
	do
		local thr = GameConfig.Index.luckThresholds
		local n = #thr
		local gap, marginX = 10, 16
		local bw = math.floor((660 - marginX * 2 - gap * (n - 1)) / n)
		for i, t in ipairs(thr) do
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.fromOffset(bw, 34)
			btn.Position = UDim2.new(0, marginX + (i - 1) * (bw + gap), 1, -64)
			btn.BackgroundColor3 = Color3.fromRGB(48, 48, 60); btn.BorderSizePixel = 0
			btn.Font = Enum.Font.GothamBold; btn.TextSize = 14; btn.TextColor3 = Color3.new(1, 1, 1)
			btn.Text = ("%d%%  +%.1f"):format(t.pct, t.luck); btn.AutoButtonColor = false
			btn.Parent = _panel
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = btn
			_claimBtns[t.pct] = btn
			btn.MouseButton1Click:Connect(function()
				if _claimed[t.pct] or (_overall.percent or 0) < t.pct then return end -- tylko reached & !claimed
				local res = Net.get("ClaimIndexLuck"):InvokeServer(t.pct)
				if type(res) == "table" and res.ok then
					_claimed[t.pct] = true
					_luckBonus = res.luckBonus or _luckBonus
					refreshLuck(); renderClaims()
				end
			end)
		end
	end
	_toast = mkLabel(_panel, UDim2.new(1, -32, 0, 20), UDim2.new(0, 16, 1, -26), "", 13,
		Color3.fromRGB(120, 255, 150))
	_toast.TextXAlignment = Enum.TextXAlignment.Left; _toast.Visible = false

	-- zakladki z IndexConfig (kolejnosc = config)
	for i, c in ipairs(GameConfig.Index.categories) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromOffset(130, 44); btn.Position = UDim2.fromOffset(0, (i - 1) * 52)
		btn.BackgroundColor3 = Color3.fromRGB(40, 40, 52); btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Font = Enum.Font.GothamBold; btn.TextSize = 14; btn.Text = c.label; btn.Parent = tabCol
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = btn
		_tabBtns[c.id] = btn
		btn.MouseButton1Click:Connect(function() renderCategory(c.id) end)
	end
	_activeCat = GameConfig.Index.categories[1].id

	IndexController.Open = openPanel -- HUD ziomka (SideButtons.Index) wola to
	openBtn.Visible = false -- stary temp guzik ukryty; panel zostaje
	openBtn.MouseButton1Click:Connect(openPanel)

	-- live: nowy wpis per-wariant + %/luck
	Net.get("IndexUpdated").OnClientEvent:Connect(function(p)
		if not p then
			return
		end
		if p.category and p.unitId and _catsById[p.category] then
			local cat = _catsById[p.category]
			if not cat.discovered[p.unitId] then
				cat.discovered[p.unitId] = true
				cat.count = (cat.count or 0) + 1
				_overall.count = (_overall.count or 0) + 1
			end
		end
		_overall.percent = p.percent or _overall.percent
		_luckBonus = p.luckBonus or _luckBonus
		refreshLuck()
		renderClaims() -- ETAP 4: nowy % moze odblokowac przycisk ODBIERZ
		if _panel.Visible and p.category == _activeCat then
			renderCategory(_activeCat)
		end
		if p.unitId then
			showToast(p.unitId, p.variant)
		end
	end)
end

return IndexController
