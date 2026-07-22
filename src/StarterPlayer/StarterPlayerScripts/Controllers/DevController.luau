--!nonstrict
-- StarterPlayerScripts/Controllers/DevController.luau
-- Panel DEV (przycisk + rozwijane akcje): waluty, resety. Widoczny TYLKO dla deva
-- (Studio ZAWSZE lub wlasciciel gry user-owned). Serwer i tak waliduje uprawnienia (DevService).
-- Akcje wysylane przez Net.DevAction (RF) -> {ok, msg?}.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))

local DevController = {}

local function isDevClient(): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and Players.LocalPlayer.UserId == game.CreatorId then
		return true
	end
	return false
end

-- {label, action, amount?, color}
local BUTTONS = {
	{ "💰 +10k monet", "coins", 10000, Color3.fromRGB(200, 165, 40) },
	{ "💰 +100k monet", "coins", 100000, Color3.fromRGB(200, 165, 40) },
	{ "🎲 +100 kosci", "rolls", 100, Color3.fromRGB(150, 110, 200) },
	{ "🎲 +1000 kosci", "rolls", 1000, Color3.fromRGB(150, 110, 200) },
	{ "🌳 Reset skille", "resetSkills", nil, Color3.fromRGB(70, 120, 170) },
	{ "🎒 Reset inventory", "resetInventory", nil, Color3.fromRGB(70, 120, 170) },
	{ "📖 Reset kolekcja", "resetIndex", nil, Color3.fromRGB(70, 120, 170) },
	{ "✖️ Reset mnozniki", "resetMultipliers", nil, Color3.fromRGB(70, 120, 170) },
	{ "☢️ RESET WSZYSTKO", "resetAll", nil, Color3.fromRGB(190, 55, 55) },
}

function DevController.start()
	if not isDevClient() then
		return -- ukryj panel dla nie-devow (serwer i tak by odrzucil)
	end

	local remote = Net.get("DevAction")

	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_DevPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 80
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- przycisk toggle (gora-lewo, pod monetami)
	local toggle = Instance.new("TextButton")
	toggle.Size = UDim2.fromOffset(96, 34)
	toggle.Position = UDim2.fromOffset(12, 62)
	toggle.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	toggle.TextColor3 = Color3.fromRGB(120, 255, 140)
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 15
	toggle.Text = "🛠 DEV"
	toggle.Parent = gui
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 8); tc.Parent = toggle

	-- panel akcji
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(200, #BUTTONS * 38 + 40)
	panel.Position = UDim2.fromOffset(12, 100)
	panel.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 10); pc.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8); pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6); list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = panel

	local status = Instance.new("TextLabel")
	status.Size = UDim2.new(1, 0, 0, 18); status.LayoutOrder = 0
	status.BackgroundTransparency = 1; status.TextColor3 = Color3.fromRGB(160, 170, 190)
	status.Font = Enum.Font.Gotham; status.TextSize = 12; status.Text = "— gotowe —"
	status.TextXAlignment = Enum.TextXAlignment.Left; status.Parent = panel

	local function doAction(action, amount)
		task.spawn(function()
			local ok, resp = pcall(function()
				return remote:InvokeServer({ action = action, amount = amount })
			end)
			if ok and resp and resp.ok then
				status.Text = "✓ " .. action
				status.TextColor3 = Color3.fromRGB(120, 230, 140)
			else
				status.Text = "✗ " .. tostring(resp and resp.msg or action)
				status.TextColor3 = Color3.fromRGB(240, 120, 120)
			end
		end)
	end

	for i, b in ipairs(BUTTONS) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 32); btn.LayoutOrder = i
		btn.BackgroundColor3 = b[4]; btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Font = Enum.Font.GothamBold; btn.TextSize = 13; btn.Text = b[1]
		btn.Parent = panel
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = btn
		btn.MouseButton1Click:Connect(function()
			doAction(b[2], b[3])
		end)
	end

	toggle.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

return DevController
