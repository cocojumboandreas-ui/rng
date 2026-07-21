--!nonstrict
-- WR_IndexTestHud  (TYMCZASOWY — test UI kolekcji; USUŃ po weryfikacji)
-- Przyciski: odkryj +3 typy / odkryj wszystkie -> potem otwórz "INDEKS".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local discover = ReplicatedStorage:WaitForChild("WR_DiscoverTest")

local gui = Instance.new("ScreenGui")
gui.Name = "WR_IndexTestHud"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function mkBtn(text, y, howMany)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(160, 36); b.Position = UDim2.fromOffset(12, y)
	b.BackgroundColor3 = Color3.fromRGB(60, 90, 60); b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.Text = text; b.Parent = gui
	b.MouseButton1Click:Connect(function() discover:FireServer(howMany) end)
	return b
end

mkBtn("ODKRYJ +3 (test)", 300, 3) -- pod przyciskiem "INDEKS" (250)
mkBtn("ODKRYJ WSZYSTKIE", 342, 999)
