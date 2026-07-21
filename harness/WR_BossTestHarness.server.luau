--!nonstrict
-- WR_BossTestHarness  (TYMCZASOWY — test bossa; USUN po weryfikacji)
-- WR_ForceBossWave: ustaw waveNumber=20, postaw kilka silnych wiez (pokrycie sciezki), StartWave.
-- Efekt: boss + grunci spawnuja, wieze strzelaja -> pasek HP bossa maleje -> clear -> BossDefeated.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local reg = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("ServiceRegistry"))

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = ReplicatedStorage end
	return r
end
local force = ensureRemote("WR_ForceBossWave")

force.OnServerEvent:Connect(function(player)
	local Wave = reg.get("WaveService")
	local Grid = reg.get("GridService")
	local Combat = reg.get("CombatService")
	local data = reg.get("ProfileService").GetProfile(player)
	if not data then return end
	Combat.ClearPlot(player)
	Grid._ResetForTest(player)
	data.placements = {}
	-- wieze pokrywajace sciezke (jak w stress-harnessie)
	local cells = { {3,4},{6,4},{3,7},{6,7},{3,10},{6,10} }
	for i, c in ipairs(cells) do
		Grid.Occupy(player, "btwr" .. i, "tank", c[1], c[2])
		data.placements["btwr" .. i] = { itemId = "tank", x = c[1], z = c[2], mut = nil }
	end
	data.waveNumber = 20
	Wave.StartWave(player)
	print("[WR_BossTest] boss wave 20 start (waga: musi byc faza Building)")
end)
