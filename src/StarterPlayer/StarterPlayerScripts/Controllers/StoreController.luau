--!nonstrict
-- StarterPlayerScripts/Controllers/StoreController.luau  (KLIENT)
-- Sklep: klik -> chowa CALY HUD (RAZEM z monetami — kupno za Robux) + panel na srodku.
-- Wlasciwa tresc UI sklepu doda ziomek; tu na razie placeholder + X (wyjscie przywraca HUD).
local Players = game:GetService("Players")

local HudOverlay = require(script.Parent:WaitForChild("HudOverlay"))

local StoreController = {}
local LP = Players.LocalPlayer
local _panel = nil

local function closePanel()
	if _panel then _panel.Visible = false end
	HudOverlay.exit() -- przywroc HUD
end

local function openPanel()
	HudOverlay.enter(false) -- schowaj CALY HUD razem z monetami (Robux, nie coiny)
	if _panel then _panel.Visible = true end
end

function StoreController.start()
	local pg = LP:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_Store"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 150; gui.Parent = pg -- NAD HUD ziomka (100), pod modalem (200)

	_panel = Instance.new("Frame")
	_panel.Size = UDim2.fromOffset(560, 380); _panel.AnchorPoint = Vector2.new(0.5, 0.5); _panel.Position = UDim2.fromScale(0.5, 0.5)
	_panel.BackgroundColor3 = Color3.fromRGB(22, 22, 30); _panel.BorderSizePixel = 0; _panel.Visible = false; _panel.Parent = gui
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 12); pc.Parent = _panel
	local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(255, 215, 90); ps.Thickness = 2; ps.Transparency = 0.3; ps.Parent = _panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromOffset(300, 30); title.Position = UDim2.fromOffset(18, 14); title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold; title.TextSize = 22; title.TextColor3 = Color3.fromRGB(255, 215, 90)
	title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = "SKLEP"; title.Parent = _panel

	local soon = Instance.new("TextLabel")
	soon.Size = UDim2.fromScale(1, 0.4); soon.Position = UDim2.fromScale(0, 0.32); soon.BackgroundTransparency = 1
	soon.Font = Enum.Font.GothamMedium; soon.TextSize = 18; soon.TextColor3 = Color3.fromRGB(200, 200, 210)
	soon.Text = "Sklep za Robux — wkrótce"; soon.Parent = _panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(30, 30); closeBtn.Position = UDim2.new(1, -40, 0, 12)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60); closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 16; closeBtn.Text = "X"; closeBtn.Parent = _panel
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(closePanel)

	StoreController.Open = openPanel -- HUD ziomka (SideButtons.Store) wola to
	StoreController.Close = closePanel
end

return StoreController
