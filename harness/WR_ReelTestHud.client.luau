--!nonstrict
-- WR_ReelTestHud  (TYMCZASOWY — device test reel/placement/combat; USUŃ po weryfikacji)
-- Klient-only: reel-reveal juz robi RollRevealController. Tu tylko akcje do przetestowania petli:
--   - śledzi OSTATNI wyrollowany invKey (unitId#mut#variant),
--   - "POSTAW OSTATNI" -> Net.PlaceUnit skanujac wolne kratki (serwer waliduje własność/budżet/fazę),
--   - "START FALA" -> Net.StartWave (blok soaks / bron strzela do wrogów).
-- Zadne RNG/logika tu nie zyje — wszystko serwer-autorytatywne przez istniejace remotes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))
local GameConfig = require(ReplicatedStorage.Content.Config.GameConfig)

local lastKey, lastName = nil, nil

local gui = Instance.new("ScreenGui")
gui.Name = "WR_ReelTestHud"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.DisplayOrder = 70
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local status = Instance.new("TextLabel")
status.Size = UDim2.fromOffset(260, 26); status.Position = UDim2.fromOffset(12, 300)
status.BackgroundColor3 = Color3.fromRGB(20, 20, 28); status.BackgroundTransparency = 0.25
status.TextColor3 = Color3.fromRGB(230, 230, 240); status.Font = Enum.Font.Gotham; status.TextSize = 13
status.Text = "Reel test: brak rolla"; status.TextXAlignment = Enum.TextXAlignment.Left; status.Parent = gui

local function mk(text, y, color, fn)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(260, 34); b.Position = UDim2.fromOffset(12, y)
	b.BackgroundColor3 = color; b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold; b.TextSize = 14; b.Text = text; b.Parent = gui
	b.MouseButton1Click:Connect(fn)
end

-- OSTATNI roll -> invKey (jak Inventory.GetCounts): unitId#mut#variant
Net.get("RollResult").OnClientEvent:Connect(function(result)
	if type(result) ~= "table" or not result.unitId then return end
	local mutId = (result.mutation and result.mutation.id) or ""
	lastKey = result.unitId .. "#" .. mutId .. "#" .. (result.variant or "regular")
	local u = GameConfig.Units[result.unitId]
	lastName = (u and u.displayName) or result.unitId
	status.Text = "Ostatni: " .. lastName .. "  [" .. lastKey .. "]"
end)

mk("POSTAW OSTATNI (skan kratek)", 334, Color3.fromRGB(60, 100, 70), function()
	if not lastKey then status.Text = "Najpierw zrób ROLL"; return end
	local W, D = GameConfig.Grid.width, GameConfig.Grid.depth
	local place = Net.get("PlaceUnit")
	for z = 1, D do
		for x = 1, W do
			local res = place:InvokeServer(lastKey, x, z)
			if res and res.ok then
				status.Text = ("Postawiono %s @ (%d,%d)"):format(lastName, x, z)
				return
			elseif res and res.reason ~= "Occupied" and res.reason ~= "OutOfBounds" then
				status.Text = "PlaceUnit: " .. tostring(res.reason)
				return -- NotOwned/BudgetExceeded/NotBuilding -> stop, pokaz powod
			end
		end
	end
	status.Text = "Brak wolnej kratki (pełna siatka)"
end)

mk("START FALA", 374, Color3.fromRGB(120, 70, 60), function()
	Net.get("StartWave"):FireServer()
	status.Text = "StartWave wysłane (bron strzela / blok tank)"
end)
