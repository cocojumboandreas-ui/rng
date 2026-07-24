--!nonstrict
-- StarterPlayerScripts/Controllers/LevelPanelController.luau  (KLIENT — TYMCZASOWY panel lewelowania, Etap 3)
-- DLUG UI (wzorzec HUD): minimalny panel do lewelowania TYPOW jednostek zanim powstanie pelny indeks (Etap 2).
-- Lista posiadanych typow (z inventory + juz lewelowane) + poziom + koszt + przycisk "Ulepsz".
-- Serwer autorytatywny: klient wysyla TYLKO intencje LevelUpUnit(unitId); koszt liczony tu tylko do WYSWIETLENIA
-- (formula = LevelConfig, config wspoldzielony). Re-hook do panelu detali itemu w indeksie = 1 linia pozniej.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig"))

local LevelPanel = {}
local LP = Players.LocalPlayer

local _gui, _list = nil, nil
local _levels = {} -- unitId -> level (cache lokalny)
local _coins = 0 -- saldo (z CoinsSync) — do podswietlenia sta/nie stac
local _rows = {} -- unitId -> { levelLbl, costLbl, btn }

-- 2.9K / 1.2M
local function fmt(n)
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

-- zbior posiadanych typow: unitId z kluczy inventory (unitId#mut#variant) + typy juz lewelowane
local function ownedUnitIds(inventory)
	local set = {}
	for invKey in pairs(inventory or {}) do
		local unitId = string.split(invKey, "#")[1]
		if unitId and GameConfig.Units[unitId] then set[unitId] = true end
	end
	for unitId in pairs(_levels) do
		if GameConfig.Units[unitId] then set[unitId] = true end
	end
	local list = {}
	for unitId in pairs(set) do list[#list + 1] = unitId end
	table.sort(list, function(a, b) -- rzadsze nizej: sortuj po rarityN rosnaco
		return ((GameConfig.Units[a].rarityN or 0)) < ((GameConfig.Units[b].rarityN or 0))
	end)
	return list
end

local function refreshRow(unitId)
	local row = _rows[unitId]
	if not row then return end
	local lv = _levels[unitId] or 0
	local maxed = lv >= GameConfig.Level.maxLevel
	row.levelLbl.Text = "Lv " .. lv
	if maxed then
		row.costLbl.Text = "MAX"
		row.btn.Text = "MAX"
		row.btn.BackgroundColor3 = Color3.fromRGB(70, 74, 86)
	else
		local cost = costOf(unitId, lv)
		row.costLbl.Text = fmt(cost)
		row.btn.Text = "Ulepsz"
		row.btn.BackgroundColor3 = (_coins >= cost) and Color3.fromRGB(80, 160, 90) or Color3.fromRGB(150, 70, 70)
	end
end

local function tryUpgrade(unitId, btn)
	local res = Net.get("LevelUpUnit"):InvokeServer(unitId)
	if type(res) == "table" and res.ok then
		_levels[unitId] = res.newLevel
		refreshRow(unitId)
	else
		-- odrzucone (NotEnoughCoins / MaxLevel / ...): krotki blysk
		local reason = type(res) == "table" and res.reason or "?"
		btn.Text = (reason == "NotEnoughCoins") and "Brak monet" or (reason == "MaxLevel" and "MAX" or "Blad")
		task.delay(0.8, function() refreshRow(unitId) end)
	end
end

local function makeRow(unitId, order)
	local u = GameConfig.Units[unitId]
	local row = Instance.new("Frame")
	row.Name = unitId; row.LayoutOrder = order; row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundColor3 = Color3.fromRGB(40, 43, 52); row.BorderSizePixel = 0; row.Parent = _list
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 6); rc.Parent = row

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.42, 0, 1, 0); nameLbl.Position = UDim2.fromOffset(8, 0)
	nameLbl.BackgroundTransparency = 1; nameLbl.Font = Enum.Font.GothamMedium; nameLbl.TextSize = 13
	nameLbl.TextColor3 = Color3.new(1, 1, 1); nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Text = u.displayName or unitId; nameLbl.TextTruncate = Enum.TextTruncate.AtEnd; nameLbl.Parent = row

	local levelLbl = Instance.new("TextLabel")
	levelLbl.Size = UDim2.new(0.16, 0, 1, 0); levelLbl.Position = UDim2.new(0.42, 0, 0, 0)
	levelLbl.BackgroundTransparency = 1; levelLbl.Font = Enum.Font.GothamBold; levelLbl.TextSize = 13
	levelLbl.TextColor3 = Color3.fromRGB(255, 220, 120); levelLbl.Text = "Lv 0"; levelLbl.Parent = row

	local costLbl = Instance.new("TextLabel")
	costLbl.Size = UDim2.new(0.18, 0, 1, 0); costLbl.Position = UDim2.new(0.58, 0, 0, 0)
	costLbl.BackgroundTransparency = 1; costLbl.Font = Enum.Font.Gotham; costLbl.TextSize = 12
	costLbl.TextColor3 = Color3.fromRGB(255, 210, 90); costLbl.Text = "0"; costLbl.Parent = row

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.22, -8, 0.72, 0); btn.Position = UDim2.new(0.78, 0, 0.14, 0)
	btn.BackgroundColor3 = Color3.fromRGB(80, 160, 90); btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold; btn.TextSize = 12; btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = "Ulepsz"; btn.AutoButtonColor = true; btn.Parent = row
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = btn

	_rows[unitId] = { levelLbl = levelLbl, costLbl = costLbl, btn = btn }
	btn.MouseButton1Click:Connect(function() tryUpgrade(unitId, btn) end)
	refreshRow(unitId)
end

local function rebuild()
	for _, ch in ipairs(_list:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end
	_rows = {}
	local inventory = Net.get("GetInventory"):InvokeServer()
	local ids = ownedUnitIds(inventory)
	for i, unitId in ipairs(ids) do makeRow(unitId, i) end
	_list.CanvasSize = UDim2.new(0, 0, 0, #ids * 38 + 4)
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_LevelPanel"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = false
	gui.DisplayOrder = 60; gui.Enabled = false; gui.Parent = LP:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(340, 380); panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
	panel.BorderSizePixel = 0; panel.Parent = gui
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 12); pc.Parent = panel
	local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(15, 16, 22); ps.Thickness = 2; ps.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -44, 0, 36); title.Position = UDim2.fromOffset(12, 6)
	title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBold; title.TextSize = 16
	title.TextColor3 = Color3.new(1, 1, 1); title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Lewelowanie (temp)"; title.Parent = panel

	local closeB = Instance.new("TextButton")
	closeB.Size = UDim2.fromOffset(28, 28); closeB.Position = UDim2.new(1, -34, 0, 8)
	closeB.BackgroundColor3 = Color3.fromRGB(150, 60, 60); closeB.BorderSizePixel = 0
	closeB.Font = Enum.Font.GothamBold; closeB.TextSize = 16; closeB.TextColor3 = Color3.new(1, 1, 1)
	closeB.Text = "X"; closeB.Parent = panel
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 6); cc.Parent = closeB
	closeB.MouseButton1Click:Connect(function() gui.Enabled = false end)

	local hdr = Instance.new("TextLabel")
	hdr.Size = UDim2.new(1, -24, 0, 18); hdr.Position = UDim2.fromOffset(12, 44)
	hdr.BackgroundTransparency = 1; hdr.Font = Enum.Font.Gotham; hdr.TextSize = 11
	hdr.TextColor3 = Color3.fromRGB(150, 155, 170); hdr.TextXAlignment = Enum.TextXAlignment.Left
	hdr.Text = "Poziom buffuje WSZYSTKIE kopie typu (weapon=dmg, block=hp)."; hdr.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -74); scroll.Position = UDim2.fromOffset(10, 66)
	scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 5
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0); scroll.Parent = panel
	local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0, 4)
	ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = scroll

	_gui, _list = gui, scroll
end

function LevelPanel.toggle()
	if not _gui then return end
	_gui.Enabled = not _gui.Enabled
	if _gui.Enabled then rebuild() end
end

function LevelPanel.start()
	build()

	-- saldo monet (do koloru przyciskow) — CoinsSync {balance}
	local coinsSync = Net.get("CoinsSync")
	coinsSync.OnClientEvent:Connect(function(p)
		if type(p) == "table" and type(p.balance) == "number" then
			_coins = p.balance
			for unitId in pairs(_rows) do refreshRow(unitId) end
		end
	end)

	-- poziomy poczatkowe
	task.spawn(function()
		local lv = Net.get("GetUnitLevels"):InvokeServer()
		if type(lv) == "table" then _levels = lv end
	end)

	-- toggle: klawisz L (temp; docelowo przycisk w indeksie)
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.L then LevelPanel.toggle() end
	end)
end

return LevelPanel
