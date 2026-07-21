--!nonstrict
-- WR_RevealTestHud  (TYMCZASOWY — test reveal; USUŃ po weryfikacji)
-- Przyciski wymuszania rewealu: prawdziwa rolka + każdy tier mutacji (x2/x4/x8).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local force = ReplicatedStorage:WaitForChild("WR_ForceReveal")

local gui = Instance.new("ScreenGui")
gui.Name = "WR_RevealTestHud"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.DisplayOrder = 60
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function mk(text, y, kind, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(180, 36); b.Position = UDim2.fromOffset(12, y)
	b.BackgroundColor3 = color; b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold; b.TextSize = 14; b.Text = text; b.ZIndex = 60; b.Parent = gui
	b.MouseButton1Click:Connect(function() force:FireServer(kind) end)
end

mk("FORCE ROLL (real)", 390, "real", Color3.fromRGB(60, 110, 70))
mk("FORCE x2  (tier1)", 432, "x2", Color3.fromRGB(70, 120, 80))
mk("FORCE x4  (tier3)", 474, "x4", Color3.fromRGB(70, 100, 150))
mk("FORCE x8  (tier5)", 516, "x8", Color3.fromRGB(150, 120, 40))
