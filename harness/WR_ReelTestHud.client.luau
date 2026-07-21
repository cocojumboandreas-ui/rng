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

-- status nad dolnym trio przyciskow (wysrodkowany)
local status = Instance.new("TextLabel")
status.Size = UDim2.fromOffset(340, 24); status.AnchorPoint = Vector2.new(0.5, 1)
status.Position = UDim2.new(0.5, 0, 1, -102)
status.BackgroundColor3 = Color3.fromRGB(20, 20, 28); status.BackgroundTransparency = 0.3
status.TextColor3 = Color3.fromRGB(230, 230, 240); status.Font = Enum.Font.Gotham; status.TextSize = 13
status.Text = "Reel test: brak rolla"; status.Parent = gui
local stCorner = Instance.new("UICorner"); stCorner.CornerRadius = UDim.new(0, 8); stCorner.Parent = status

-- mk(text, color, fn, props) — props ustawia AnchorPoint/Position/Size wg slotu HUD
local function mk(text, color, fn, props)
	local b = Instance.new("TextButton")
	b.AnchorPoint = props.anchor; b.Position = props.pos; b.Size = props.size
	b.BackgroundColor3 = color; b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold; b.TextSize = 15; b.Text = text; b.Parent = gui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = b
	b.MouseButton1Click:Connect(fn)
	return b
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

-- POSTAW OSTATNI (slot "Zbuduj") — dol-srodek, na LEWO od ROLL
mk("POSTAW OSTATNI", Color3.fromRGB(60, 100, 70), function()
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
end, { anchor = Vector2.new(1, 1), pos = UDim2.new(0.5, -120, 1, -32), size = UDim2.fromOffset(200, 54) })

-- START FALA (slot "Rozpocznij falę") — prawa krawedz, srodek, zielony
mk("START FALA", Color3.fromRGB(60, 150, 70), function()
	Net.get("StartWave"):FireServer()
	status.Text = "StartWave wysłane (bron strzela / blok tank)"
end, { anchor = Vector2.new(1, 0.5), pos = UDim2.new(1, -24, 0.5, -20), size = UDim2.fromOffset(185, 50) })
