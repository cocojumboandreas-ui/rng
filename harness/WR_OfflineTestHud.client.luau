--!nonstrict
-- WR_OfflineTestHud  (TYMCZASOWY — test popup offline; USUŃ po weryfikacji)
-- Przyciski symulacji offline -> popup "Witaj z powrotem".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sim = ReplicatedStorage:WaitForChild("WR_SimOfflineTest")

local gui = Instance.new("ScreenGui")
gui.Name = "WR_OfflineTestHud"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function mk(text, y, h)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(200, 36); b.Position = UDim2.fromOffset(12, y)
	b.BackgroundColor3 = Color3.fromRGB(50, 70, 100); b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.Text = text; b.Parent = gui
	b.MouseButton1Click:Connect(function() sim:FireServer(h) end)
end

mk("SYMULUJ OFFLINE 2h", 390, 2)
mk("SYMULUJ OFFLINE 20h (cap)", 432, 20)
