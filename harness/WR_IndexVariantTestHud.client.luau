--!nonstrict
-- WR_IndexVariantTestHud  (TYMCZASOWY — test kolekcji 4 kategorie; USUŃ po weryfikacji)
-- Przyciski odkrywania unit-wariantow: +3 regular / +3 shiny / +3 galaxy / ODKRYJ WSZYSTKO.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local discover = ReplicatedStorage:WaitForChild("WR_DiscoverVariant")

local gui = Instance.new("ScreenGui")
gui.Name = "WR_IndexVariantTestHud"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.DisplayOrder = 62
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- debug: prawy-gorny rog, zwarta kolumna (poza glownym HUD)
local function mk(text, y, variant, howMany, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(180, 34); b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -12, 0, y)
	b.BackgroundColor3 = color; b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.Text = text; b.ZIndex = 62; b.Parent = gui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
	b.MouseButton1Click:Connect(function()
		discover:FireServer({ variant = variant, howMany = howMany })
	end)
end

mk("ODKRYJ +3 REGULAR", 48, "regular", 3, Color3.fromRGB(70, 90, 70))
mk("✨ ODKRYJ +3 SHINY", 86, "shiny", 3, Color3.fromRGB(120, 110, 50))
mk("🌌 ODKRYJ +3 GALAXY", 124, "galaxy", 3, Color3.fromRGB(100, 75, 160))
mk("ODKRYJ WSZYSTKO (reg)", 162, "regular", -1, Color3.fromRGB(60, 100, 120))
