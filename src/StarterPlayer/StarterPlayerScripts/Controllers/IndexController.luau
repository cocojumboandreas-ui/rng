--!nonstrict
-- StarterPlayerScripts/Controllers/IndexController.luau  (post-bramka task 2 — klient)
-- Minimalne UI kolekcji: siatka typow jednostek (odkryte = nazwa, zablokowane = "?"),
-- % ukonczenia, aktualny bonus luck. Stan: GetIndexState (RF) na otwarcie; IndexUpdated (S->C)
-- live (nowa jednostka + %/luck). WEJSCIE: TYMCZASOWY przycisk "INDEKS" — re-hook do prawdziwej
-- zoltej ikony ksiazki w HUD, gdy HUD sie pojawi (obecnie brak HUD w placu).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local IndexController = {}

local _discovered = {} -- { [unitId] = true }
local _total, _percent, _luckBonus = 0, 0, 0
local _panel, _header, _luckLabel, _toast
local _cellByUnit = {}
local _unitOrder = {} -- lista unitId (stabilna, po rarityN rosnaco)

local function mkLabel(parent, size, pos, text, size2, color)
	local l = Instance.new("TextLabel")
	l.Size = size; l.Position = pos
	l.BackgroundTransparency = 1
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Font = Enum.Font.Gotham; l.TextSize = size2 or 14
	l.Text = text; l.Parent = parent
	return l
end

local function countDiscovered()
	local n = 0
	for _ in pairs(_discovered) do n += 1 end
	return n
end

local function refresh()
	local count = countDiscovered()
	if _header then
		_header.Text = ("Ukonczenie: %d/%d  (%d%%)"):format(count, _total, math.floor(_percent + 0.5))
		_luckLabel.Text = ("Bonus luck z indeksu: +%.2f"):format(_luckBonus)
	end
	for unitId, cell in pairs(_cellByUnit) do
		local u = GameConfig.Units[unitId]
		if _discovered[unitId] then
			cell.label.Text = (u and u.displayName) or unitId
			cell.frame.BackgroundColor3 = Color3.fromRGB(40, 80, 50)
			cell.label.TextColor3 = Color3.new(1, 1, 1)
		else
			cell.label.Text = "?"
			cell.frame.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
			cell.label.TextColor3 = Color3.fromRGB(120, 120, 130)
		end
	end
end

local function showToast(unitId)
	if not _toast then return end
	local u = GameConfig.Units[unitId]
	_toast.Text = "Nowa jednostka: " .. ((u and u.displayName) or unitId)
	_toast.Visible = true
	task.delay(2.5, function()
		if _toast then _toast.Visible = false end
	end)
end

local function buildGrid()
	-- kolejnosc: po rarityN rosnaco (stabilna prezentacja)
	_unitOrder = {}
	for id in pairs(GameConfig.Units) do _unitOrder[#_unitOrder + 1] = id end
	table.sort(_unitOrder, function(a, b) return GameConfig.Units[a].rarityN < GameConfig.Units[b].rarityN end)
	_total = #_unitOrder

	local cols, cw, ch, gap = 3, 130, 60, 8
	for i, unitId in ipairs(_unitOrder) do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(cw, ch)
		frame.Position = UDim2.fromOffset(col * (cw + gap), row * (ch + gap))
		frame.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
		frame.BorderSizePixel = 0
		frame.Parent = _panel:FindFirstChild("Grid")
		local label = mkLabel(frame, UDim2.fromScale(1, 1), UDim2.new(), "?", 13)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextWrapped = true
		_cellByUnit[unitId] = { frame = frame, label = label }
	end
end

local function openPanel()
	_panel.Visible = true
	local state = Net.get("GetIndexState"):InvokeServer()
	if state then
		_discovered = state.discovered or {}
		_total = state.total or _total
		_percent = state.percent or 0
		_luckBonus = state.luckBonus or 0
	end
	refresh()
end

function IndexController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_Index"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- TYMCZASOWY przycisk wejscia (re-hook do HUD ksiazki gdy bedzie)
	local openBtn = Instance.new("TextButton")
	openBtn.Size = UDim2.fromOffset(120, 40); openBtn.Position = UDim2.fromOffset(12, 250)
	openBtn.BackgroundColor3 = Color3.fromRGB(90, 75, 40); openBtn.TextColor3 = Color3.new(1, 1, 1)
	openBtn.Font = Enum.Font.GothamBold; openBtn.TextSize = 16; openBtn.Text = "INDEKS"
	openBtn.Parent = gui

	_panel = Instance.new("Frame")
	_panel.Size = UDim2.fromOffset(440, 360); _panel.Position = UDim2.fromScale(0.5, 0.5)
	_panel.AnchorPoint = Vector2.new(0.5, 0.5)
	_panel.BackgroundColor3 = Color3.fromRGB(22, 22, 30); _panel.BorderSizePixel = 0
	_panel.Visible = false; _panel.Parent = gui

	local title = mkLabel(_panel, UDim2.fromOffset(240, 26), UDim2.fromOffset(12, 8), "KOLEKCJA (INDEKS)", 18)
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(28, 28); closeBtn.Position = UDim2.new(1, -36, 0, 8)
	closeBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40); closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 16; closeBtn.Text = "X"; closeBtn.Parent = _panel
	closeBtn.MouseButton1Click:Connect(function() _panel.Visible = false end)

	_header = mkLabel(_panel, UDim2.fromOffset(300, 20), UDim2.fromOffset(12, 40), "Ukonczenie: 0/0 (0%)", 15)
	_header.TextXAlignment = Enum.TextXAlignment.Left
	_luckLabel = mkLabel(_panel, UDim2.fromOffset(300, 20), UDim2.fromOffset(12, 62), "Bonus luck z indeksu: +0.00", 15, Color3.fromRGB(255, 220, 120))
	_luckLabel.TextXAlignment = Enum.TextXAlignment.Left

	local grid = Instance.new("Frame")
	grid.Name = "Grid"; grid.Size = UDim2.new(1, -24, 1, -110); grid.Position = UDim2.fromOffset(12, 92)
	grid.BackgroundTransparency = 1; grid.Parent = _panel

	_toast = mkLabel(_panel, UDim2.new(1, -24, 0, 22), UDim2.new(0, 12, 1, -26), "", 14, Color3.fromRGB(120, 255, 150))
	_toast.TextXAlignment = Enum.TextXAlignment.Left
	_toast.Visible = false

	buildGrid()
	openBtn.MouseButton1Click:Connect(openPanel)

	-- live: nowa jednostka / %/luck
	Net.get("IndexUpdated").OnClientEvent:Connect(function(p)
		if not p then return end
		if p.unitId then _discovered[p.unitId] = true end
		_percent = p.percent or _percent
		_luckBonus = p.luckBonus or _luckBonus
		refresh()
		if p.unitId then showToast(p.unitId) end
	end)
end

return IndexController
