--!nonstrict
-- WR_MutTestHud  (TYMCZASOWY — test kaskady mutacji; USUŃ po weryfikacji)
-- Przyciski wymuszania mutacji (x8 / x128) -> reveal z kaskada koniczyn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local force = ReplicatedStorage:WaitForChild("WR_ForceMut")

local gui = Instance.new("ScreenGui")
gui.Name = "WR_MutTestHud"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 62
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function mk(text, y, mult, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(180, 34); b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -12, 0, y)
	b.BackgroundColor3 = color; b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.Text = text; b.ZIndex = 62; b.Parent = gui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
	b.MouseButton1Click:Connect(function() force:FireServer(mult) end)
end

mk("🍀 FORCE MUT x8", 48, 8, Color3.fromRGB(150, 110, 60))
mk("🍀 FORCE MUT x128", 86, 128, Color3.fromRGB(120, 90, 160))
