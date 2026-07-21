--!nonstrict
-- ServerScriptService/Services/WaveService.luau  (§3.8)
-- Cykl zycia fali per plot: faza, spawn puli, kill counter, warunki konca, summary, nagroda.
-- NIE symuluje ruchu (to Combat). StartWave tylko z fazy Building.
-- deps: CombatService, CoreService, EconomyService, StatProfileService,
--       + ProfileService (writer profile.waveNumber), PlotService (plotId do Net).
-- Uproszczenie slice: faza Summary zwinieta w event WaveEnded — po koncu wracamy od razu do Building.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local WaveService = {}

local _combat, _core, _economy, _stat, _profile, _plot = nil, nil, nil, nil, nil, nil
local _waveProgress, _waveEnded, _bossDefeated = nil, nil, nil
local _phase: { [any]: string } = {} -- player -> RunPhase (domyslnie Building)
local _run: { [any]: any } = {} -- player -> {kills, pool} podczas WaveActive

local function isBossWave(waveNumber: number): boolean
	local bw = GameConfig.Wave.bossWave
	return waveNumber > 0 and bw ~= nil and bw > 0 and (waveNumber % bw == 0)
end

-- sklad fali z WaveConfig(waveNumber): zwraca (composition {{typeId,count}}, poolSize, formation)
local function waveComposition(waveNumber: number)
	-- boss-fala: 1 boss + zredukowani grunci (zawsze, niezaleznie od jawnych waves[n])
	if isBossWave(waveNumber) then
		local grunts = GameConfig.Wave.bossGrunts or 0
		local comp = { { "boss", 1 } }
		if grunts > 0 then
			comp[#comp + 1] = { "grunt", grunts }
		end
		return comp, 1 + grunts, { cols = 6 }
	end
	local w = GameConfig.Wave.waves[waveNumber]
	if w then
		local pool = 0
		for _, e in ipairs(w.composition) do
			pool += e[2]
		end
		return w.composition, pool, w.formation
	end
	-- generowana wzorem (WZOR w configu): pool = poolBase + n*poolPerWave, sami grunci
	local s = GameConfig.Wave.scaling
	local pool = math.floor(s.poolBase + waveNumber * s.poolPerWave)
	return { { "grunt", pool } }, pool, { cols = 6 }
end

local function plotIdOf(player): number
	local plot = _plot and _plot.GetPlot(player)
	return plot and plot.plotId or 0
end

local function pushProgress(player, waveNumber, killed, pool)
	if _waveProgress then
		_waveProgress:FireClient(player, { plotId = plotIdOf(player), waveNumber = waveNumber, killed = killed, pool = pool })
	end
end

function WaveService.GetPhase(player): string
	return _phase[player] or Enums.RunPhase.Building
end

function WaveService.StartWave(player)
	if WaveService.GetPhase(player) ~= Enums.RunPhase.Building then
		return -- tylko z Building
	end
	local data = _profile and _profile.GetProfile(player)
	if not data then
		return
	end
	local waveNumber = data.waveNumber or 1
	local comp, pool = waveComposition(waveNumber)

	_phase[player] = Enums.RunPhase.WaveActive
	_run[player] = { kills = 0, pool = pool }
	_core.ResetHP(player)
	for _, entry in ipairs(comp) do
		_combat.SpawnEnemies(player, waveNumber, { enemyTypeId = entry[1], count = entry[2], formation = { cols = 6 } })
	end
	WaveService.WaveStarted:Fire(player, waveNumber, pool)
	pushProgress(player, waveNumber, 0, pool)
end

local function endWave(player, reason)
	local run = _run[player] or { kills = 0, pool = 0 }
	local data = _profile and _profile.GetProfile(player)
	local waveNumber = (data and data.waveNumber) or 1
	local coinsEarned = 0

	if reason == Enums.WaveEndReason.Cleared then
		coinsEarned = _economy.AwardWave(player, waveNumber, run.kills) -- boss-fala: x bossRewardMult (Economy)
		if isBossWave(waveNumber) then
			WaveService.BossDefeated:Fire(player, waveNumber)
			if _bossDefeated then
				_bossDefeated:FireClient(player, { plotId = plotIdOf(player), waveNumber = waveNumber })
			end
		end
		if data then
			data.waveNumber = waveNumber + 1
		end
	else -- CoreDestroyed: koniec runu
		_combat.ClearPlot(player)
		if data then
			data.waveNumber = 1
		end
		_core.ResetHP(player)
	end

	_phase[player] = Enums.RunPhase.Building
	_run[player] = nil
	local summary = { coinsEarned = coinsEarned, kills = run.kills, waveNumber = waveNumber }
	WaveService.WaveEnded:Fire(player, reason, summary)
	if _waveEnded then
		_waveEnded:FireClient(player, { plotId = plotIdOf(player), reason = reason, summary = summary })
	end
end

local function onEnemyDied(player)
	if WaveService.GetPhase(player) ~= Enums.RunPhase.WaveActive then
		return
	end
	local run = _run[player]
	if not run then
		return
	end
	run.kills += 1
	local data = _profile and _profile.GetProfile(player)
	pushProgress(player, (data and data.waveNumber) or 1, run.kills, run.pool)
	if run.kills >= run.pool then
		endWave(player, Enums.WaveEndReason.Cleared)
	end
end

local function onCoreDestroyed(player)
	if WaveService.GetPhase(player) ~= Enums.RunPhase.WaveActive then
		return
	end
	endWave(player, Enums.WaveEndReason.CoreDestroyed)
end

function WaveService.Init()
	WaveService.WaveStarted = Signal.new() -- (player, waveNumber, poolSize)
	WaveService.WaveEnded = Signal.new() -- (player, reason, summary)
	WaveService.BossDefeated = Signal.new() -- (player, waveNumber) — flourish klienta
end

function WaveService.Start()
	_combat = ServiceRegistry.get("CombatService")
	_core = ServiceRegistry.get("CoreService")
	_economy = ServiceRegistry.get("EconomyService")
	_stat = ServiceRegistry.get("StatProfileService")
	_profile = ServiceRegistry.get("ProfileService")
	_plot = ServiceRegistry.get("PlotService")
	_waveProgress = Net.get("WaveProgress")
	_waveEnded = Net.get("WaveEnded")
	_bossDefeated = Net.get("BossDefeated")

	Net.get("StartWave").OnServerEvent:Connect(function(player)
		WaveService.StartWave(player)
	end)
	_combat.EnemyDied:Connect(function(player)
		onEnemyDied(player)
	end)
	_core.CoreDestroyed:Connect(function(player)
		onCoreDestroyed(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_phase[player] = nil
		_run[player] = nil
	end)
end

-- Hooki TYLKO do testow.
function WaveService._InjectForTest(deps)
	_combat, _core, _economy, _stat, _profile, _plot =
		deps.combat, deps.core, deps.economy, deps.stat, deps.profile, deps.plot
end
function WaveService._OnEnemyDiedForTest(player)
	onEnemyDied(player)
end
function WaveService._OnCoreDestroyedForTest(player)
	onCoreDestroyed(player)
end
function WaveService._WaveCompositionForTest(waveNumber)
	local comp, pool = waveComposition(waveNumber)
	return { comp = comp, pool = pool, isBoss = isBossWave(waveNumber) }
end

return WaveService
