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

local function mk(text, y, variant, howMany, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(190, 34); b.Position = UDim2.fromOffset(410, y)
	b.BackgroundColor3 = color; b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.Text = text; b.ZIndex = 62; b.Parent = gui
	b.MouseButton1Click:Connect(function()
		discover:FireServer({ variant = variant, howMany = howMany })
	end)
end

mk("ODKRYJ +3 REGULAR", 300, "regular", 3, Color3.fromRGB(70, 90, 70))
mk("✨ ODKRYJ +3 SHINY", 340, "shiny", 3, Color3.fromRGB(120, 110, 50))
mk("🌌 ODKRYJ +3 GALAXY", 380, "galaxy", 3, Color3.fromRGB(100, 75, 160))
mk("ODKRYJ WSZYSTKO (reg)", 420, "regular", -1, Color3.fromRGB(60, 100, 120))
