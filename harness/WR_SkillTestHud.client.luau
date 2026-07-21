--!nonstrict
-- WR_SkillTestHud  (TYMCZASOWY — test UI drzewka; USUŃ po weryfikacji)
-- Przycisk grantu waluty testowej (5000 coins + 500 rolls) -> potem otwórz "SKILLE".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local grant = ReplicatedStorage:WaitForChild("WR_GrantTest")

local gui = Instance.new("ScreenGui")
gui.Name = "WR_SkillTestHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local btn = Instance.new("TextButton")
btn.Size = UDim2.fromOffset(160, 40)
btn.Position = UDim2.fromOffset(12, 250) -- pod przyciskiem "SKILLE" (200)
btn.BackgroundColor3 = Color3.fromRGB(120, 90, 30)
btn.TextColor3 = Color3.new(1, 1, 1)
btn.Font = Enum.Font.GothamBold
btn.TextSize = 14
btn.Text = "GRANT TEST $$"
btn.Parent = gui

btn.MouseButton1Click:Connect(function()
	grant:FireServer()
end)
