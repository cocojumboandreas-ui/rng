--!nonstrict
-- WR_ReelTestHud  (TYMCZASOWY — tylko START FALA; USUŃ po weryfikacji)
-- Stawianie przejal prawdziwy BuildController (ZBUDUJ). Tu zostal tylko przycisk startu fali.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local gui = Instance.new("ScreenGui")
gui.Name = "WR_ReelTestHud"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.DisplayOrder = 70
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- START FALA — prawa krawedz, srodek, zielony
local b = Instance.new("TextButton")
b.AnchorPoint = Vector2.new(1, 0.5); b.Position = UDim2.new(1, -24, 0.5, -20); b.Size = UDim2.fromOffset(185, 50)
b.BackgroundColor3 = Color3.fromRGB(60, 150, 70); b.TextColor3 = Color3.new(1, 1, 1)
b.Font = Enum.Font.GothamBold; b.TextSize = 15; b.Text = "START FALA"; b.Parent = gui
local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = b
b.MouseButton1Click:Connect(function()
	Net.get("StartWave"):FireServer()
end)
