--!nonstrict
-- ServerScriptService/Services/CombatService.luau  (§3.9 + §9)  ⚠ SERCE WYDAJNOŚCI
-- JEDYNA petla symulacji. Wrog = WIERSZ W TABELI {id, typeId, hp, maxHp, pathT, speed, plotId, coreTimer}.
-- Pozycja = parametr t na polilinii pathNodes (NIE Vector3, brak fizyki, brak Humanoidow).
-- Jeden Heartbeat-accumulator, SIM_HZ = GameConfig.Sim.simHz. Krok:
--   1) ruch: pathT += speed*dt (plaska petla)
--   2) wieze: per jednostka bojowa — cooldown, cel=najblizszy wrog w zasiegu (dist^2 w XZ), dmg×dmgMult
--   3) wrogowie przy pathT>=1: atak rdzenia w interwale (EnemyReachedCore -> Core)
--   4) batch: EnemySync (Unreliable, broadcast) + EnemyEvents deaths (reliable)
-- deps: PlotService (geometria/pathNodes), StatProfileService (dmgMult), GridService (jednostki+pozycje).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local GridMath = require(Framework:WaitForChild("GridMath"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local CombatService = {}

local _plot, _stat, _grid = nil, nil, nil
local _enemySync, _enemyEvents = nil, nil

local _enemies: { [any]: { [number]: any } } = {} -- player -> {enemyId -> row}
local _towerCd: { [any]: { [string]: number } } = {} -- player -> {placementId -> cooldown}
local _deaths: { [any]: { number } } = {} -- player -> {enemyId,...} (flush per tick)
local _nextEnemyId = 0
local _acc = 0
local _synthPlotId: { [any]: number } = {} -- syntetyczny klucz -> plotId (harness bramki; puste w grze)
local _lastStepMs = 0 -- czas ostatniego kroku symulacji [ms] (instrumentacja bramki)
local _syncBytes = 0 -- bajty EnemySync od ostatniego odczytu (KB/s bramki)

-- Rozwiazanie geometrii plotu: realny gracz -> GetPlot; klucz syntetyczny -> GetPlotById.
local function resolvePlot(key)
	if not _plot then
		return nil
	end
	local sp = _synthPlotId[key]
	if sp and _plot.GetPlotById then
		return _plot.GetPlotById(sp)
	end
	return _plot.GetPlot(key)
end

-- ── geometria ────────────────────────────────────────────────────────────────
-- pozycja swiata na polilinii pathNodes dla t∈[0,1] (rowno po segmentach; 2 wezly = lerp)
local function enemyWorldPos(plot, t: number): Vector3
	local nodes = plot.pathNodes
	local n = nodes and #nodes or 0
	if n == 0 then
		return plot.coreCFrame and plot.coreCFrame.Position or Vector3.zero
	end
	if n == 1 then
		return nodes[1].Position
	end
	local tt = math.clamp(t, 0, 1)
	local scaled = tt * (n - 1)
	local i = math.floor(scaled) + 1
	if i >= n then
		return nodes[n].Position
	end
	local frac = scaled - (i - 1)
	return nodes[i].Position:Lerp(nodes[i + 1].Position, frac)
end

local function towerWorldPos(plot, unitId: string, x: number, z: number): Vector3
	local fp = GameConfig.Units[unitId].footprint
	return GridMath.cellToWorld(plot.gridOrigin, GameConfig.Grid.cellSize, x, z, fp).Position
end

local function waveHpMult(waveNumber: number): number
	local w = GameConfig.Wave.waves[waveNumber]
	if w and w.hpMult then
		return w.hpMult
	end
	return GameConfig.Wave.scaling.hpGrowth ^ (waveNumber - 1)
end

-- ── API (§3.9) ────────────────────────────────────────────────────────────────
function CombatService.SpawnEnemies(player, waveNumber: number, spec)
	local et = GameConfig.Wave.enemyTypes[spec.enemyTypeId]
	if not et then
		warn(("[CombatService] nieznany enemyType '%s'"):format(tostring(spec.enemyTypeId)))
		return
	end
	local hp = et.hp * waveHpMult(waveNumber)
	local stagger = GameConfig.Sim.spawnStagger or 0.03
	local plot = resolvePlot(player)
	local plotId = plot and plot.plotId or 0
	_enemies[player] = _enemies[player] or {}
	local enemies = _enemies[player]

	local spawnList = {}
	for i = 1, spec.count do
		_nextEnemyId += 1
		local id = _nextEnemyId
		enemies[id] = {
			id = id,
			typeId = spec.enemyTypeId,
			hp = hp,
			maxHp = hp,
			pathT = -(i - 1) * stagger, -- staggered wejscie (formacja)
			speed = et.speed,
			plotId = plotId,
			coreTimer = et.coreAttackInterval,
		}
		spawnList[#spawnList + 1] = { id = id, typeId = spec.enemyTypeId, pathT = enemies[id].pathT }
	end
	if _enemyEvents then
		_enemyEvents:FireAllClients({ plotId = plotId, spawns = spawnList, deaths = {} })
	end
end

function CombatService.GetAliveCount(player): number
	local enemies = _enemies[player]
	if not enemies then
		return 0
	end
	local n = 0
	for _ in pairs(enemies) do
		n += 1
	end
	return n
end

function CombatService.ClearPlot(player)
	-- rozeslij smierci pozostalych wrogow, zeby klient zwolnil ich party (np. po CoreDestroyed)
	local enemies = _enemies[player]
	if enemies and _enemyEvents then
		local ids = {}
		for id in pairs(enemies) do
			ids[#ids + 1] = id
		end
		if #ids > 0 then
			local plot = _plot and _plot.GetPlot(player)
			_enemyEvents:FireAllClients({ plotId = plot and plot.plotId or 0, spawns = {}, deaths = ids })
		end
	end
	_enemies[player] = nil
	_towerCd[player] = nil
	_deaths[player] = nil
end

-- ── tick ──────────────────────────────────────────────────────────────────────
local function queueDeath(player, id)
	_deaths[player] = _deaths[player] or {}
	table.insert(_deaths[player], id)
end

local function step(dt: number)
	for player, enemies in pairs(_enemies) do
		local plot = resolvePlot(player)
		if plot then
			local dmgMult = (_stat and _stat.Get(player).dmgMult) or 1

			-- 1) ruch
			for _, e in pairs(enemies) do
				e.pathT += e.speed * dt
			end

			-- 2) wieze
			local placements = (_grid and _grid.GetPlacements(player)) or {}
			_towerCd[player] = _towerCd[player] or {}
			local cds = _towerCd[player]
			for pid, pl in pairs(placements) do
				local u = GameConfig.Units[pl.unitId]
				if u and u.combat then
					cds[pid] = (cds[pid] or 0) - dt
					if cds[pid] <= 0 then
						local tpos = towerWorldPos(plot, pl.unitId, pl.x, pl.z)
						local bestD = u.combat.range * u.combat.range
						local best = nil
						for _, e in pairs(enemies) do
							local epos = enemyWorldPos(plot, e.pathT)
							local dx, dz = epos.X - tpos.X, epos.Z - tpos.Z
							local d2 = dx * dx + dz * dz
							if d2 <= bestD then
								bestD = d2
								best = e
							end
						end
						if best then
							best.hp -= u.combat.dmg * dmgMult
							cds[pid] = 1 / u.combat.fireRate
							if best.hp <= 0 then
								enemies[best.id] = nil
								queueDeath(player, best.id)
								CombatService.EnemyDied:Fire(player, best.typeId)
							end
						end
					end
				end
			end

			-- 3) atak rdzenia (wrog przy pathT>=1)
			for _, e in pairs(enemies) do
				if e.pathT >= 1 then
					e.coreTimer -= dt
					if e.coreTimer <= 0 then
						local et = GameConfig.Wave.enemyTypes[e.typeId]
						e.coreTimer = (et and et.coreAttackInterval) or 1
						CombatService.EnemyReachedCore:Fire(player, e.typeId)
					end
				end
			end

			-- 4) sync PER PLOT jako buffer: u16 id(id%65536) + u8 pathT(0..255) + u8 hpPct = 4B/wrog.
			-- Tabela z ~300 wrogami przekracza limit UnreliableRemoteEvent (~900B) i jest DROPowana;
			-- per-plot buffer (50 wrogow = 200B) miesci sie. u16 id (nie u32) -> ~11KB/s przy simHz=10.
			-- BRAK KOLIZJI po obcieciu do u16: alive/plot ~50, id MONOTONICZNE, okno zycia wroga to
			-- sekundy -> zadne dwa ZYWE wrogi nie roznia sie o dokladnie 65536 w id (klient i tak
			-- weryfikuje po pelnym id przy spawnie i ostrzega przy kolizji).
			local cnt = 0
			for _ in pairs(enemies) do
				cnt += 1
			end
			if _enemySync and cnt > 0 then
				local buf = buffer.create(cnt * 4)
				local off = 0
				for _, e in pairs(enemies) do
					buffer.writeu16(buf, off, e.id % 65536)
					buffer.writeu8(buf, off + 2, math.floor(math.clamp(e.pathT, 0, 1) * 255 + 0.5))
					buffer.writeu8(buf, off + 3, math.clamp(math.floor(e.hp / e.maxHp * 100 + 0.5), 0, 100))
					off += 4
				end
				_enemySync:FireAllClients(plot.plotId, buf)
				_syncBytes += buffer.len(buf)
			end
		end
	end

	-- flush smierci (reliable, per plot)
	for player, deaths in pairs(_deaths) do
		if #deaths > 0 then
			if _enemyEvents then
				local plot = _plot and _plot.GetPlot(player)
				_enemyEvents:FireAllClients({ plotId = plot and plot.plotId or 0, spawns = {}, deaths = deaths })
			end
			_deaths[player] = nil
		end
	end
end

function CombatService.Init()
	CombatService.EnemyDied = Signal.new() -- (player, enemyTypeId)
	CombatService.EnemyReachedCore = Signal.new() -- (player, enemyTypeId)
end

function CombatService.Start()
	_plot = ServiceRegistry.get("PlotService")
	_stat = ServiceRegistry.get("StatProfileService")
	_grid = ServiceRegistry.get("GridService")
	_enemySync = Net.get("EnemySync")
	_enemyEvents = Net.get("EnemyEvents")

	local dtStep = 1 / (GameConfig.Sim.simHz or 10)
	RunService.Heartbeat:Connect(function(dt)
		_acc += dt
		while _acc >= dtStep do
			local t0 = os.clock()
			step(dtStep)
			_lastStepMs = (os.clock() - t0) * 1000
			_acc -= dtStep
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		CombatService.ClearPlot(player)
	end)
end

-- ── Harness bramki (Task 8) — syntetyczne obciazenie + instrumentacja ──────────
-- Syntetyczna fala na dowolnym plocie BEZ gracza (klucz-tabela -> plotId).
function CombatService.SpawnSyntheticWave(plotId: number, count: number, waveNumber: number?)
	local key = { synthPlot = plotId }
	_synthPlotId[key] = plotId
	CombatService.SpawnEnemies(key, waveNumber or 1, { enemyTypeId = "grunt", count = count, formation = { cols = 6 } })
	return key
end
function CombatService.ClearSynthetic()
	for key in pairs(_synthPlotId) do
		CombatService.ClearPlot(key)
		_synthPlotId[key] = nil
	end
end
function CombatService.GetLastStepMs(): number
	return _lastStepMs
end
function CombatService.GetSyncBytesAndReset(): number
	local b = _syncBytes
	_syncBytes = 0
	return b
end

-- Hooki TYLKO do testow (deterministyczny krok, wstrzykniecie deps).
function CombatService._InjectForTest(deps)
	_plot, _stat, _grid = deps.plot, deps.stat, deps.grid
end
function CombatService._StepForTest(dt)
	step(dt)
end
function CombatService._GetEnemiesForTest(player)
	return _enemies[player]
end
function CombatService._EnemyWorldPosForTest(plot, t)
	return enemyWorldPos(plot, t)
end

return CombatService
