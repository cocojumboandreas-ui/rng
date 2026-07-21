--!nonstrict
-- StarterPlayerScripts/Controllers/IndexController.luau  (ETAP 2 — klient, model wzorca)
-- 4 zakladki (Regularny / Blyszczacy / Galaktyka / Wrogowie), siatka slotow z ramka rzadkosci,
-- panel detali (view-only), dolny pasek bonusu luck. Wrogowie = STUB (sloty puste, tresc etap 5).
-- Stan: GetIndexState (RF) na otwarcie; IndexUpdated (S->C) live (nowy wpis per-wariant + %/luck).
-- BEZ przycisku levelowania (etap 3) i BEZ ODBIERZ (etap 4).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local IndexController = {}

-- ── stan ──────────────────────────────────────────────────────────────────────
local _catsById = {} -- id -> {id,label,kind,variant,discovered={uid=true},count,total,percent}
local _catOrder = {} -- lista id w kolejnosci zakladek
local _overall = { count = 0, total = 0, percent = 0 }
local _luckBonus = 0
local _activeCat = nil
local _unitOrder = {} -- unitId po rarityN rosnaco (stabilne)
local _panel, _grid, _luckLabel, _toast, _tabBtns = nil, nil, nil, nil, {}
local _detail = {} -- {frame, name, rarity, stats}

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

-- ── panel detali (view-only; przycisk levelowania dochodzi w etapie 3) ──────────
local function showDetail(unitId, variant)
	local u = GameConfig.Units[unitId]
	if not u then
		return
	end
	local tier = tierFor(u.rarityN)
	_detail.name.Text = (u.displayName or unitId) .. (VARIANT_BADGE[variant] and (" " .. VARIANT_BADGE[variant]) or "")
	_detail.name.TextColor3 = VARIANT_TINT[variant] or Color3.new(1, 1, 1)
	_detail.rarity.Text = ("Rzadkosc: %s (1 in %d)"):format(tier.name, u.rarityN)
	_detail.rarity.TextColor3 = TIER_COLOR[tier.revealTier]
	local c = u.combat or {}
	_detail.stats.Text = ("Obrazenia: %s\nSzybkostrzelnosc: %s/s\nZasieg: %s")
		:format(tostring(c.dmg or "-"), tostring(c.fireRate or "-"), tostring(c.range or "-"))
end

local function clearDetail()
	_detail.name.Text = "Wybierz odkryty wpis"
	_detail.name.TextColor3 = Color3.fromRGB(150, 150, 160)
	_detail.rarity.Text = ""
	_detail.stats.Text = ""
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
		_luckLabel.Text = ("Mnoznik szczescia indeksu: +%.2f    (%d%%  %d/%d)"):format(
			_luckBonus, math.floor(_overall.percent + 0.5), _overall.count, _overall.total)
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
	refreshLuck()
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

local function openPanel()
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
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- TYMCZASOWY przycisk wejscia (re-hook do HUD ksiazki gdy bedzie)
	local openBtn = Instance.new("TextButton")
	openBtn.Size = UDim2.fromOffset(120, 40); openBtn.Position = UDim2.fromOffset(12, 250)
	openBtn.BackgroundColor3 = Color3.fromRGB(90, 75, 40); openBtn.TextColor3 = Color3.new(1, 1, 1)
	openBtn.Font = Enum.Font.GothamBold; openBtn.TextSize = 16; openBtn.Text = "INDEKS"; openBtn.Parent = gui

	_panel = Instance.new("Frame")
	_panel.Size = UDim2.fromOffset(660, 430); _panel.Position = UDim2.fromScale(0.5, 0.5)
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
	closeBtn.MouseButton1Click:Connect(function() _panel.Visible = false end)

	-- lewa kolumna zakladek
	local tabCol = Instance.new("Frame")
	tabCol.Size = UDim2.fromOffset(130, 300); tabCol.Position = UDim2.fromOffset(16, 48)
	tabCol.BackgroundTransparency = 1; tabCol.Parent = _panel
	_tabBtns = {}

	-- srodkowa siatka
	_grid = Instance.new("Frame")
	_grid.Name = "Grid"; _grid.Size = UDim2.fromOffset(324, 320); _grid.Position = UDim2.fromOffset(156, 48)
	_grid.BackgroundTransparency = 1; _grid.Parent = _panel

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
	_detail.stats = mkLabel(detailFrame, UDim2.new(1, -16, 0, 120), UDim2.fromOffset(8, 100), "", 13,
		Color3.fromRGB(210, 210, 220))
	_detail.stats.TextXAlignment = Enum.TextXAlignment.Left; _detail.stats.TextYAlignment = Enum.TextYAlignment.Top

	-- dolny pasek bonusu luck (bez ODBIERZ — etap 4)
	_luckLabel = mkLabel(_panel, UDim2.new(1, -32, 0, 24), UDim2.new(0, 16, 1, -54),
		"Mnoznik szczescia indeksu: +0.00", 15, Color3.fromRGB(255, 220, 120))
	_luckLabel.TextXAlignment = Enum.TextXAlignment.Left
	_toast = mkLabel(_panel, UDim2.new(1, -32, 0, 22), UDim2.new(0, 16, 1, -28), "", 14,
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
		if _panel.Visible and p.category == _activeCat then
			renderCategory(_activeCat)
		end
		if p.unitId then
			showToast(p.unitId, p.variant)
		end
	end)
end

return IndexController
