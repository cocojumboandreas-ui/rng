--!nonstrict
-- WR_BossTestHud  (TYMCZASOWY — test bossa; USUN po weryfikacji)
-- Przycisk FORCE BOSS WAVE -> boss-fala 20 (render bossa + pasek HP + BossDefeated).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local force = ReplicatedStorage:WaitForChild("WR_ForceBossWave")

local gui = Instance.new("ScreenGui")
gui.Name = "WR_BossTestHud"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 55
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local b = Instance.new("TextButton")
b.Size = UDim2.fromOffset(200, 40); b.Position = UDim2.fromOffset(12, 300)
b.BackgroundColor3 = Color3.fromRGB(150, 40, 200); b.TextColor3 = Color3.new(1, 1, 1)
b.Font = Enum.Font.GothamBlack; b.TextSize = 15; b.Text = "FORCE BOSS WAVE"; b.ZIndex = 55; b.Parent = gui
b.MouseButton1Click:Connect(function() force:FireServer() end)
