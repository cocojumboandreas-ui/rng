--!nonstrict
-- WR_StressHarness  (TYMCZASOWY — bramka Task 8; USUŃ po zielonej bramce)
-- Syntetyczne obciazenie: 50 wrogow x 6 plotow (300) + 20 wiez x 6 (120) — BEZ 6 graczy.
-- Instrumentacja: serwerowy czas ticku [ms] + EnemySync [KB/s]; broadcast do WR_StressStats.
-- Sterowanie: klientowy WR_StressHud wysyla WR_StressToggle(true/false). INERTNY do momentu kliknięcia.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local reg = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("ServiceRegistry"))

local ENEMIES_PER_PLOT = 50
local TOWERS_PER_PLOT = 20
local STRESS_WAVE = 40 -- wysoki hpMult, zeby 300 wrogow przetrwalo okno pomiaru
local PLOTS = { 1, 2, 3, 4, 5, 6 }
local TOWER_COLS = { 4, 5, 6, 7 } -- kolumny blisko sciezki (sniper range 26)

local function ensureRemote(name, class)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local toggle = ensureRemote("WR_StressToggle", "RemoteEvent")
local stats = ensureRemote("WR_StressStats", "RemoteEvent")

local Combat, Grid, Plot
local active = false
local synthKeys = {}

local function startStress()
	if active then
		return
	end
	Combat = reg.get("CombatService")
	Grid = reg.get("GridService")
	Plot = reg.get("PlotService")
	active = true
	synthKeys = {}
	for _, pid in ipairs(PLOTS) do
		local key = Combat.SpawnSyntheticWave(pid, ENEMIES_PER_PLOT, STRESS_WAVE)
		synthKeys[#synthKeys + 1] = key
		local placed = 0
		for z = 1, 12 do
			for _, x in ipairs(TOWER_COLS) do
				if placed < TOWERS_PER_PLOT then
					placed += 1
					Grid.Occupy(key, "t" .. pid .. "_" .. placed, "sniper", x, z)
				end
			end
		end
	end
	print(("[WR_Stress] START: %d wrogow + %d wiez (6 plotow)"):format(#PLOTS * ENEMIES_PER_PLOT, #PLOTS * TOWERS_PER_PLOT))
end

local function stopStress()
	if not active then
		return
	end
	active = false
	Combat.ClearSynthetic()
	for _, key in ipairs(synthKeys) do
		if Grid._ResetForTest then
			Grid._ResetForTest(key)
		end
	end
	synthKeys = {}
	print("[WR_Stress] STOP")
end

toggle.OnServerEvent:Connect(function(_, on)
	if on then
		startStress()
	else
		stopStress()
	end
end)

-- stats co 1s (per-klient KB/s = sumaryczne bajty broadcastu, bo kazdy klient dostaje ten sam pakiet)
task.spawn(function()
	while true do
		task.wait(1)
		if active and Combat then
			local tickMs = Combat.GetLastStepMs()
			local kbps = Combat.GetSyncBytesAndReset() / 1024
			stats:FireAllClients({ tickMs = tickMs, syncKBps = kbps })
			print(("[WR_Stress] tick=%.2fms  EnemySync=%.1fKB/s"):format(tickMs, kbps))
		end
	end
end)
