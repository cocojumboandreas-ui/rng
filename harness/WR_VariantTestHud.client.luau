--!nonstrict
-- WR_VariantTestHud  (TYMCZASOWY — test finish wariantu; USUŃ po weryfikacji)
-- Przyciski wymuszania rewealu z finishem wariantu: shiny / shiny+x4 / galaxy / galaxy+x8+tier5.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local force = ReplicatedStorage:WaitForChild("WR_ForceVariant")

local gui = Instance.new("ScreenGui")
gui.Name = "WR_VariantTestHud"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.DisplayOrder = 61
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function mk(text, y, kind, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(200, 36); b.Position = UDim2.fromOffset(200, y)
	b.BackgroundColor3 = color; b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold; b.TextSize = 14; b.Text = text; b.ZIndex = 61; b.Parent = gui
	b.MouseButton1Click:Connect(function() force:FireServer(kind) end)
end

mk("✨ SHINY", 390, "shiny", Color3.fromRGB(150, 130, 40))
mk("✨ SHINY + x4", 432, "shiny_x4", Color3.fromRGB(120, 110, 60))
mk("🌌 GALAXY", 474, "galaxy", Color3.fromRGB(90, 70, 150))
mk("🌌 GALAXY + x8 (max)", 516, "galaxy_max", Color3.fromRGB(110, 80, 170))
