--!nonstrict
-- StarterPlayerScripts/Controllers/SkillTreeController.luau  (post-bramka task 1 — klient)
-- Minimalne UI drzewka LEAN: przycisk wejscia, zakladki galezi (Roll/Base/Combat), wezly
-- (rank / koszt nastepnej rangi / efekt) + przycisk Kup, wyswietlacz monet + spendableRolls.
-- Stan: GetSkillState (RF) przy otwarciu; CoinsSync/RollsSync na zywo; SkillPurchase (RF) = zakup.
-- v1 proste (polish pozniej). Serwer waliduje wszystko — tu tylko intencja + wyswietlanie.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local BRANCHES = { "Roll", "Base", "Combat" }

local SkillTreeController = {}

local _coins, _rolls = 0, 0
local _ranks = {}
local _activeBranch = "Roll"
local _panel, _coinsLabel, _rollsLabel, _nodeList

-- ── helpers ──
local function costFor(node, targetRank)
	return math.round(node.base * targetRank ^ GameConfig.Skill.costExp)
end

local function effectText(node)
	local e = node.effect
	local sign = e.perRank >= 0 and "+" or ""
	return ("%s %s%s/rank"):format(e.stat, sign, tostring(e.perRank))
end

local function canAfford(node, cost)
	if node.currency == "Rolls" then
		return _rolls >= cost
	end
	return _coins >= cost
end

-- ── UI budowa ──
local function mkLabel(parent, size, pos, text, size2)
	local l = Instance.new("TextLabel")
	l.Size = size; l.Position = pos
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.Gotham; l.TextSize = size2 or 14
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function refreshNodes()
	for _, c in ipairs(_nodeList:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	-- wezly danej galezi, sortowane po id
	local ids = {}
	for id, node in pairs(GameConfig.Skill.nodes) do
		if node.branch == _activeBranch then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	local y = 0
	for _, id in ipairs(ids) do
		local node = GameConfig.Skill.nodes[id]
		local rank = _ranks[id] or 0
		local maxed = rank >= node.maxRank
		local cost = maxed and nil or costFor(node, rank + 1)

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 62)
		row.Position = UDim2.fromOffset(4, y)
		row.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
		row.BorderSizePixel = 0
		row.Parent = _nodeList
		y += 66

		mkLabel(row, UDim2.new(1, -90, 0, 20), UDim2.fromOffset(8, 4), id .. "   [rank " .. rank .. "/" .. node.maxRank .. "]", 15)
		mkLabel(row, UDim2.new(1, -90, 0, 18), UDim2.fromOffset(8, 24), effectText(node), 13)
		local costText = maxed and "MAX" or ("koszt: " .. cost .. " " .. node.currency)
		mkLabel(row, UDim2.new(1, -90, 0, 18), UDim2.fromOffset(8, 42), costText, 13)

		local buy = Instance.new("TextButton")
		buy.Size = UDim2.fromOffset(78, 54); buy.Position = UDim2.new(1, -82, 0, 4)
		buy.Font = Enum.Font.GothamBold; buy.TextSize = 14; buy.TextColor3 = Color3.new(1, 1, 1)
		buy.BorderSizePixel = 0
		if maxed then
			buy.Text = "MAX"; buy.BackgroundColor3 = Color3.fromRGB(70, 70, 70); buy.AutoButtonColor = false
		elseif canAfford(node, cost) then
			buy.Text = "Kup"; buy.BackgroundColor3 = Color3.fromRGB(40, 130, 60)
		else
			buy.Text = "Kup"; buy.BackgroundColor3 = Color3.fromRGB(90, 55, 55)
		end
		buy.Parent = row
		if not maxed then
			buy.MouseButton1Click:Connect(function()
				local resp = Net.get("SkillPurchase"):InvokeServer(id)
				if resp and resp.ok then
					_ranks[id] = resp.rank
					refreshNodes() -- salda dojda przez CoinsSync/RollsSync
				end
			end)
		end
	end
	_nodeList.CanvasSize = UDim2.fromOffset(0, y)
end

local function updateBalances()
	if _coinsLabel then
		_coinsLabel.Text = "Monety: " .. _coins
		_rollsLabel.Text = "Rolki: " .. _rolls
		refreshNodes() -- odswiez stan przyciskow Kup (afford)
	end
end

local function setBranch(b)
	_activeBranch = b
	refreshNodes()
end

local function openPanel()
	_panel.Visible = true
	local state = Net.get("GetSkillState"):InvokeServer()
	if state then
		_ranks = state.ranks or {}
		_coins = state.coins or 0
		_rolls = state.spendableRolls or 0
	end
	updateBalances()
end

function SkillTreeController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_SkillTree"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- przycisk wejscia
	local openBtn = Instance.new("TextButton")
	-- HUD: dol-srodek, na PRAWO od ROLL — lustro ZBUDUJ (ten sam rozmiar, +130 z prawej)
	openBtn.Size = UDim2.fromOffset(140, 54); openBtn.AnchorPoint = Vector2.new(0, 1)
	openBtn.Position = UDim2.new(0.5, 130, 1, -32)
	openBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 90); openBtn.TextColor3 = Color3.new(1, 1, 1)
	openBtn.Font = Enum.Font.GothamBold; openBtn.TextSize = 16; openBtn.Text = "SKILLE"
	openBtn.Parent = gui
	local sbCorner = Instance.new("UICorner"); sbCorner.CornerRadius = UDim.new(0, 10); sbCorner.Parent = openBtn

	-- panel
	_panel = Instance.new("Frame")
	_panel.Size = UDim2.fromOffset(420, 380); _panel.Position = UDim2.fromScale(0.5, 0.5)
	_panel.AnchorPoint = Vector2.new(0.5, 0.5)
	_panel.BackgroundColor3 = Color3.fromRGB(22, 22, 30); _panel.BorderSizePixel = 0
	_panel.Visible = false; _panel.Parent = gui

	local title = mkLabel(_panel, UDim2.new(1, -100, 0, 28), UDim2.fromOffset(12, 8), "DRZEWKO UMIEJETNOSCI", 18)
	title.Font = Enum.Font.GothamBold

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(28, 28); closeBtn.Position = UDim2.new(1, -36, 0, 8)
	closeBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40); closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 16; closeBtn.Text = "X"; closeBtn.Parent = _panel
	closeBtn.MouseButton1Click:Connect(function() _panel.Visible = false end)

	_coinsLabel = mkLabel(_panel, UDim2.fromOffset(180, 20), UDim2.fromOffset(12, 40), "Monety: 0", 15)
	_rollsLabel = mkLabel(_panel, UDim2.fromOffset(180, 20), UDim2.fromOffset(200, 40), "Rolki: 0", 15)

	-- zakladki galezi
	for i, b in ipairs(BRANCHES) do
		local tab = Instance.new("TextButton")
		tab.Size = UDim2.fromOffset(128, 30); tab.Position = UDim2.fromOffset(12 + (i - 1) * 134, 66)
		tab.BackgroundColor3 = Color3.fromRGB(45, 45, 60); tab.TextColor3 = Color3.new(1, 1, 1)
		tab.Font = Enum.Font.GothamBold; tab.TextSize = 14; tab.Text = b; tab.Parent = _panel
		tab.MouseButton1Click:Connect(function() setBranch(b) end)
	end

	_nodeList = Instance.new("ScrollingFrame")
	_nodeList.Size = UDim2.new(1, -16, 1, -110); _nodeList.Position = UDim2.fromOffset(8, 102)
	_nodeList.BackgroundTransparency = 1; _nodeList.BorderSizePixel = 0
	_nodeList.ScrollBarThickness = 6; _nodeList.Parent = _panel

	openBtn.MouseButton1Click:Connect(openPanel)

	-- salda na zywo
	Net.get("CoinsSync").OnClientEvent:Connect(function(p)
		_coins = (p and p.balance) or _coins
		updateBalances()
	end)
	Net.get("RollsSync").OnClientEvent:Connect(function(p)
		_rolls = (p and p.spendableRolls) or _rolls
		updateBalances()
	end)
end

return SkillTreeController
