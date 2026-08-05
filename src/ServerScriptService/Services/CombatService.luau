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
local EnemyFormation = require(Framework:WaitForChild("EnemyFormation"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local CombatService = {}

local _plot, _stat, _grid, _build, _level = nil, nil, nil, nil, nil
local _enemySync, _enemyEvents, _bossHP, _unitHpNet = nil, nil, nil, nil
local _playerShotHit = nil -- S->C echo trafienia gracza (liczba "-N" nad wrogiem)
local _unitHp: { [any]: { [string]: number } } = {} -- player -> {placementId -> hp} (faza 5)
local _unitHpSend: { [string]: number } = {} -- placementId -> os.clock ostatniego pushu HP (throttle)

local _enemies: { [any]: { [number]: any } } = {} -- player -> {enemyId -> row}
local _towerCd: { [any]: { [string]: number } } = {} -- player -> {placementId -> cooldown}
local _deaths: { [any]: { number } } = {} -- player -> {enemyId,...} (flush per tick)
local _nextEnemyId = 0
local _acc = 0
local _rng = Random.new() -- serwerowy RNG (proc splash Explosive Ammo); NIE math.random
local _synthPlotId: { [any]: number } = {} -- syntetyczny klucz -> plotId (harness bramki; puste w grze)
local _lastStepMs = 0 -- czas ostatniego kroku symulacji [ms] (instrumentacja bramki)
local _syncBytes = 0 -- bajty EnemySync od ostatniego odczytu (KB/s bramki)
local _runDamage: { [any]: number } = {} -- player -> suma obrazen zadanych wrogom w runie (do podsumowania; overkill nieliczony)
local _playerDmg: { [any]: number } = {} -- player -> obrazenia zadane przez GRACZA (bron FPS) w runie (summary)
local _playerHS: { [any]: number } = {} -- player -> liczba headshotow gracza w runie (summary)
local _playerKills: { [any]: number } = {} -- player -> liczba wrogow zabitych przez gracza (bron FPS) w runie (summary)

-- FIX P0: klamra anty-spirala-smierci na nadganianiu akumulatora (+ rate-limit warna).
local MAX_STEPS_PER_FRAME = 3 -- max krokow symulacji na 1 Heartbeat; nadwyzka = PORZUCONY dlug (gra zwalnia, nie umiera)
local OVERRUN_WARN_EVERY = 5 -- [s] jak rzadko warnowac o porzuceniu dlugu / przepelnieniu sync (nie zalewaj outputu)
local _lastOverrunWarn = -math.huge
local _dtStep = 1 / (GameConfig.Sim.simHz or 10) -- staly krok symulacji [s] (bylo lokalne w Start)
-- FIX P0: chunkowanie EnemySync (UnreliableRemoteEvent dropuje CALY pakiet >~900B).
local ENEMIES_PER_PACKET = 180 -- 180*4B + 2B naglowek = 722B < 900B; wiecej wrogow -> kolejne chunki
local MAX_SYNC_CHUNKS = 8 -- twardy sufit: powyzej ENEMIES_PER_PACKET*8 wrogow nadwyzka NIE jest wysylana (+warn)
local _lastSyncOverflowWarn = -math.huge

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
-- SRODEK toru: pozycja swiata na polilinii pathNodes dla t∈[0,1] (rowno po segmentach)
local function pathCenter(plot, t: number): Vector3
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

-- REALNA pozycja wroga: srodek toru + boczny pas (lane) i glebokosc (fwd) z rozlewem (EnemyFormation).
-- Bez lane/fwd -> czysty srodek (do sprawdzen progresu, np. "przy rdzeniu"). MUSI byc zgodne z renderem klienta.
local function enemyWorldPos(plot, t: number, lane: number?, fwd: number?): Vector3
	local center = pathCenter(plot, t)
	if (lane == nil or lane == 0) and (fwd == nil or fwd == 0) then
		return center
	end
	local tt = math.clamp(t, 0, 1)
	local ahead = pathCenter(plot, math.min(tt + 0.02, 1))
	local d = ahead - center
	if d.Magnitude < 1e-3 then
		return center
	end
	local dir = d.Unit
	local perp = Vector3.new(-dir.Z, 0, dir.X) -- prostopadla w plaszczyznie XZ (jak render klienta)
	local spread = EnemyFormation.spreadAt(tt)
	return center + perp * ((lane or 0) * spread) + dir * ((fwd or 0) * spread)
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

-- mnoznik obrazen wroga dla fali n (skaluje atkDmg -> DEF bloku spowalnia, nie zatrzymuje na zawsze)
local function waveAtkMult(waveNumber: number): number
	return (GameConfig.Wave.scaling.dmgGrowth or 1) ^ (waveNumber - 1)
end

-- Nazwa bossa/mini-bossa: "<ranga> <nazwa>". Duzy boss = najwyzsza ranga (General); mini = ranga rosnie z fala.
-- Deterministyczna z id (stabilna, nie miga). Pule w WaveConfig.bossNames (podmienialne). Zwykli wrogowie: brak nazwy.
local function bossNameFor(waveNumber: number, id: number, isBigBoss: boolean): string
	local bn = GameConfig.Wave.bossNames
	if not bn or not bn.ranks or not bn.names or #bn.ranks == 0 or #bn.names == 0 then
		return "BOSS"
	end
	local rankIdx = isBigBoss and #bn.ranks or math.clamp(1 + math.floor(waveNumber / 8), 1, #bn.ranks - 1)
	local nameIdx = (id % #bn.names) + 1
	return bn.ranks[rankIdx] .. " " .. bn.names[nameIdx]
end

-- ── API (§3.9) ────────────────────────────────────────────────────────────────
function CombatService.SpawnEnemies(player, waveNumber: number, spec)
	local et = GameConfig.Wave.enemyTypes[spec.enemyTypeId]
	if not et then
		warn(("[CombatService] nieznany enemyType '%s'"):format(tostring(spec.enemyTypeId)))
		return
	end
	local protoHp = (GameConfig.Wave.proto and GameConfig.Wave.proto.hpMul) or 1 -- PROTOTYP: grubsi wrogowie
	local hp = (spec.hpOverride or (et.hp * waveHpMult(waveNumber))) * protoHp -- boss: jawne HP (5x zolnierz z fali n-1) tez x hpMul
	local atkDmg = (et.atkDmg or 0) * waveAtkMult(waveNumber) -- obrazenia jednostek skalowane z fala
	local isBigBoss = et.isBoss or false -- prawdziwy DUZY boss (typ z isBoss); mini-boss to forceBoss na elicie
	local isBoss = spec.forceBoss or isBigBoss -- isBoss: render bossa (wieksza + pasek HP + srodek + nazwa)
	local stagger = GameConfig.Sim.spawnStagger or 0.03
	local plot = resolvePlot(player)
	local plotId = plot and plot.plotId or 0
	_enemies[player] = _enemies[player] or {}
	local enemies = _enemies[player]

	-- CELOWANIE W KOLUMNY: wrogowie nie rozlewaja sie rowno — dostaja KOLUMNE CELU z zestawu fali
	-- (round-robin po id -> rowny podzial). Boss trzyma srodek. lane = dokladne wyrownanie do kolumny siatki.
	local width = GameConfig.Grid.width
	local cellSize = GameConfig.Grid.cellSize
	local centerCol = math.ceil(width / 2)
	local targetCols = spec.targetCols
	if not targetCols or #targetCols == 0 then targetCols = { centerCol } end
	-- ROZNE TEMPA: deterministyczny mnoznik predkosci per-wrog z id (klient interpoluje z sync -> brak desync).
	local sj = GameConfig.Wave.speedJitter

	local spawnList = {}
	for i = 1, spec.count do
		_nextEnemyId += 1
		local id = _nextEnemyId
		local col = isBoss and centerCol or targetCols[((id - 1) % #targetCols) + 1]
		local speedMul = 1
		if sj then
			local f = id * 0.7548776662466927
			speedMul = sj.min + (f - math.floor(f)) * (sj.max - sj.min)
		end
		enemies[id] = {
			id = id,
			typeId = spec.enemyTypeId,
			hp = hp,
			maxHp = hp,
			pathT = -(i - 1) * stagger, -- staggered wejscie (formacja)
			speed = et.speed * speedMul, -- rozne tempa (mnoznik z id)
			plotId = plotId,
			coreTimer = et.coreAttackInterval,
			atkDmg = atkDmg, -- atkDmg × waveAtkMult (zamrozony na spawnie, jak hp)
			isBoss = isBoss, -- boss = zwykly wiersz z flaga (ta sama petla/pathing/core-dmg)
			bossName = isBoss and bossNameFor(waveNumber, id, isBigBoss) or nil, -- "<ranga> <nazwa>" na pasku bossa
			isBigBoss = isBigBoss, -- true TYLKO dla DUZEGO bossa (co 20 fal) -> klient robi shake ekranu ("boss wbija")
			col = col, -- kolumna celu (1..width); klient dostaje ja w spawnList i liczy IDENTYCZNY lane
			-- lane = boczny offset dokladnie nad kolumna celu; glebokosc (fwd) deterministyczna z id (nie gesiego w kolumnie).
			-- Blokowanie/celowanie/dmg licza REALNA pozycje (nie srodek) -> bloki/jednostki na kolumnie celu zatrzymuja wroga.
			lane = EnemyFormation.laneForColumn(col, width, cellSize),
			fwd = EnemyFormation.fwd(id, isBoss),
		}
		spawnList[#spawnList + 1] = { id = id, typeId = spec.enemyTypeId, pathT = enemies[id].pathT, isBoss = isBoss, maxHp = hp, col = col }
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
	-- FIX P0: wyczysc throttle-timestampy HP jednostek tego placu (inaczej placementId-e orphanowaly w
	-- _unitHpSend — tabela globalna po placementId, nietkniety przez czyszczenie per-gracza). Kazdy wpis
	-- _unitHpSend ma odpowiednik w _unitHp[player] (pisany tylko przy oberwaniu jednostki), wiec iteracja
	-- po kluczach uhp pokrywa wszystkie wpisy tego gracza i nie rusza cudzych placementId-ow.
	local uhp = _unitHp[player]
	if uhp then
		for pid in pairs(uhp) do
			_unitHpSend[pid] = nil
		end
	end
	_enemies[player] = nil
	_towerCd[player] = nil
	_deaths[player] = nil
	_unitHp[player] = nil
	_runDamage[player] = nil
	_playerDmg[player] = nil
	_playerHS[player] = nil
	_playerKills[player] = nil
end

-- suma obrazen zadanych wrogom w biezacym runie (WaveService czyta do podsumowania PRZED ClearPlot)
function CombatService.GetRunDamage(player): number
	return _runDamage[player] or 0
end

-- Statystyki GRACZA (bron FPS) w runie do podsumowania: obrazenia / headshoty / zabojstwa. WaveService czyta PRZED ClearPlot.
function CombatService.GetPlayerRunStats(player)
	return {
		damage = math.floor((_playerDmg[player] or 0) + 0.5),
		headshots = _playerHS[player] or 0,
		kills = _playerKills[player] or 0,
	}
end
function CombatService.ResetRunDamage(player)
	_runDamage[player] = nil
end

-- RESET HP jednostek gracza (WaveService po fali: "wszystko odnowione" -> ocalale wracaja do pelnego HP).
-- Czysci _unitHp (re-init do maxHp przy nastepnym kroku 2b) + throttle-timestampy paskow HP.
function CombatService.ResetUnitHp(player)
	local uhp = _unitHp[player]
	if uhp then
		for pid in pairs(uhp) do
			_unitHpSend[pid] = nil
		end
	end
	_unitHp[player] = nil
end

-- ── tick ──────────────────────────────────────────────────────────────────────
local function queueDeath(player, id)
	_deaths[player] = _deaths[player] or {}
	table.insert(_deaths[player], id)
end

-- FIX P0: buduje pakiety EnemySync z limitem rozmiaru. Wrogowie NAJBLIZSI RDZENIA (najwyzszy pathT) ida
-- w chunk 0 — jesli pakiet zginie w transporcie, traci sie tych NAJDALEJ od gracza. Kazdy chunk to
-- NIEZALEZNA aktualizacja stanu znanych wrogow; pruning idzie osobno przez reliable EnemyEvents, wiec
-- pominiecie wroga w chunku = brak update tej klatki, NIE usuniecie. Format bufora (na chunk):
--   [u8 chunkIdx][u8 chunkCount] + N*(u16 id + u8 pathT + u8 hpPct).
-- Zwraca: chunks (lista buforow), total (ilu wrogow zywych), sent (ilu zmiescilo sie po twardym capie).
local function buildSyncChunks(enemies)
	local list = {}
	for _, e in pairs(enemies) do
		list[#list + 1] = e
	end
	local total = #list
	if total == 0 then
		return {}, 0, 0
	end
	table.sort(list, function(a, b) return a.pathT > b.pathT end) -- najblizsi rdzenia (wyzszy pathT) pierwsi
	local sent = math.min(total, ENEMIES_PER_PACKET * MAX_SYNC_CHUNKS)
	local chunkCount = math.ceil(sent / ENEMIES_PER_PACKET)
	local chunks = {}
	for ci = 0, chunkCount - 1 do
		local startI = ci * ENEMIES_PER_PACKET + 1
		local endI = math.min(startI + ENEMIES_PER_PACKET - 1, sent)
		local buf = buffer.create(2 + (endI - startI + 1) * 4)
		buffer.writeu8(buf, 0, ci)
		buffer.writeu8(buf, 1, chunkCount)
		local off = 2
		for i = startI, endI do
			local e = list[i]
			buffer.writeu16(buf, off, e.id % 65536)
			buffer.writeu8(buf, off + 2, math.floor(math.clamp(e.pathT, 0, 1) * 255 + 0.5))
			buffer.writeu8(buf, off + 3, math.clamp(math.floor(e.hp / e.maxHp * 100 + 0.5), 0, 100))
			off += 4
		end
		chunks[#chunks + 1] = buf
	end
	return chunks, total, sent
end

local function step(dt: number)
	for player, enemies in pairs(_enemies) do
		local plot = resolvePlot(player)
		if plot then
			local stats = _stat and _stat.Get(player)
			local dmgMult = (stats and stats.dmgMult) or 1
			local fireRateMult = (stats and stats.fireRateMult) or 1
			local rangeMult = (stats and stats.rangeMult) or 1
			local explosiveChance = (stats and stats.explosiveChance) or 0 -- Explosive Ammo: szansa splash (0 gdy brak)

			-- LEWELOWANIE (Etap 3): mnoznik efektu TYPU = growthPerLevel^level. Odczyt unitLevels JEDEN raz/gracza
			-- (NIE per-wieza), mnoznik liczony inline z LevelConfig.growthPerLevel i memoizowany per unitId
			-- (perf: brak pow ani call serwisu per-tick per-wieza). weapon -> dmg + hp, block -> hp.
			local levels = (_level and _level.GetLevels(player)) or nil
			local levelGrowth = GameConfig.Level.growthPerLevel
			local levelMultMemo = {}
			local function levelMult(unitId: string): number
				local m = levelMultMemo[unitId]
				if m == nil then
					local lv = (levels and levels[unitId]) or 0
					m = (lv > 0) and (levelGrowth ^ lv) or 1
					levelMultMemo[unitId] = m
				end
				return m
			end

			-- placementy raz na krok: wieze + BLOKOWANIE ruchu + atak jednostek
			local placements = (_grid and _grid.GetPlacements(player)) or {}
			local placeWorld = {} -- swiatowe pozycje wszystkich postawionych (bloki+jednostki blokuja przejscie)
			for _, pl in pairs(placements) do
				placeWorld[#placeWorld + 1] = towerWorldPos(plot, pl.unitId, pl.x, pl.z)
			end
			-- STANDOFF: wrog staje ~1 stud PRZED blokiem/jednostka na SWOIM pasie i strzela (nie przenika, nie biegnie w nia).
			local blockStop = GameConfig.Sim.blockStopDist or 5.5 -- dystans SRODEK-SRODEK stopu
			local blockLaneHalf2 = (GameConfig.Sim.blockLaneHalf or 3.6) ^ 2 -- (max boczne odchylenie od pasa)^2

			-- 1) ruch — wrog biegnie do bazy. STOP gdy: (a) w zasiegu broni od rdzenia (ostrzeliwuje rdzen),
			-- (b) przed nim stoi blok/jednostka — NIE przenika, musi ja zniszczyc zeby isc dalej.
			local corePos = plot.coreCFrame and plot.coreCFrame.Position
			for _, e in pairs(enemies) do
				local et = GameConfig.Wave.enemyTypes[e.typeId]
				local range = (et and et.atkRange) or 12 -- zasieg ostrzalu rdzenia = zasieg broni (BALANS: WaveConfig atkRange)
				-- "przy rdzeniu" liczymy ze SRODKA toru (progres wzdluz sciezki), zeby wrogowie z bocznych
				-- kolumn tez doszli do rdzenia (inaczej skrajne pasy nigdy nie w zasiegu -> utkniecie na t=1).
				local cpos = enemyWorldPos(plot, e.pathT)
				-- REALNA pozycja (srodek + boczny pas) -> blokowanie/kolizja z placementami tej kolumny.
				local epos = enemyWorldPos(plot, e.pathT, e.lane, e.fwd)
				local atCore = false
				if corePos then
					local dx, dz = cpos.X - corePos.X, cpos.Z - corePos.Z
					if (dx * dx + dz * dz) <= range * range then atCore = true end
				end
				-- przeszkoda tuz przed wrogiem (na jego REALNYM pasie) -> stop (przenikanie zabronione)
				local blocked = false
				if not atCore and e.pathT < 1 and #placeWorld > 0 then
					local ahead = enemyWorldPos(plot, math.min(e.pathT + 0.02, 1), e.lane, e.fwd)
					local fx, fz = ahead.X - epos.X, ahead.Z - epos.Z
					local flen = math.sqrt(fx * fx + fz * fz)
					if flen > 1e-3 then
						local dirx, dirz = fx / flen, fz / flen -- kierunek ruchu wroga (styczna sciezki na jego pasie)
						for _, up in ipairs(placeWorld) do
							local rx, rz = up.X - epos.X, up.Z - epos.Z
							local along = rx * dirx + rz * dirz -- ile PRZED wrogiem wzdluz ruchu (<0 = za nim)
								if along > 0 and along <= blockStop then
									local lx, lz = rx - dirx * along, rz - dirz * along -- boczne odchylenie od pasa
									if (lx * lx + lz * lz) <= blockLaneHalf2 then blocked = true; break end
								end
						end
					end
				end
				if not atCore and not blocked and e.pathT < 1 then
					e.pathT = math.min(1, e.pathT + e.speed * dt)
				end
				e.atCore = atCore
				e.blocked = blocked
			end

			-- 2) wieze
			_towerCd[player] = _towerCd[player] or {}
			local cds = _towerCd[player]
			for pid, pl in pairs(placements) do
				local u = GameConfig.Units[pl.unitId]
				if u and u.combat then
					cds[pid] = (cds[pid] or 0) - dt
					if cds[pid] <= 0 then
						local tpos = towerWorldPos(plot, pl.unitId, pl.x, pl.z)
						local effRange = u.combat.range * rangeMult * (GameConfig.Sim.unitRangeMult or 1)
						local bestD = effRange * effRange
						local best = nil
						for _, e in pairs(enemies) do
							local epos = enemyWorldPos(plot, e.pathT, e.lane, e.fwd)
							local dx, dz = epos.X - tpos.X, epos.Z - tpos.Z
							local d2 = dx * dx + dz * dz
							if d2 <= bestD then
								bestD = d2
								best = e
							end
						end
						if best then
							local dmg = u.combat.dmg * dmgMult * levelMult(pl.unitId) -- level TYPU buffuje dmg broni
							_runDamage[player] = (_runDamage[player] or 0) + math.min(dmg, math.max(0, best.hp)) -- licz efektywne (bez overkill)
							best.hp -= dmg
							cds[pid] = 1 / (u.combat.fireRate * fireRateMult)
							-- EXPLOSIVE AMMO: szansa na splash AoE wokol celu (wspolna sciezka smierci przez AreaDamage).
							-- best moze zginac od splash -> ponizsza gałąź smierci strzezona przez enemies[best.id].
							if explosiveChance > 0 and _rng:NextNumber() < explosiveChance then
								local ex = GameConfig.SkillEffect and GameConfig.SkillEffect.explosive
								if ex then
									local bpos = enemyWorldPos(plot, best.pathT, best.lane, best.fwd)
									CombatService.AreaDamage(player, bpos, ex.splashRadius or 9, dmg * (ex.splashFrac or 0.6))
								end
							end
							if best.hp <= 0 and enemies[best.id] then
								enemies[best.id] = nil
								queueDeath(player, best.id)
								CombatService.EnemyDied:Fire(player, best.typeId)
							end
						end
					end
				end
			end

			-- 2b) FAZA 5: wrogowie zadaja obrazenia jednostkom w zasiegu; jednostka ginie przy 0 HP
			local uhp = _unitHp[player]
			if not uhp then uhp = {}; _unitHp[player] = uhp end
			local unitList = {}
			for pid, pl in pairs(placements) do
				local u = GameConfig.Units[pl.unitId]
				if u then
					local maxHp = (u.hp or 100) * levelMult(pl.unitId) -- level TYPU buffuje HP (weapon i block)
					if uhp[pid] == nil then
						uhp[pid] = maxHp
						-- NIE pokazuj paska na pelnym HP przy pojawieniu (to robilo "zupe" zielonych X/Y nad
						-- kazda jednostka). Pasek pojawi sie dopiero przy PIERWSZYM oberwaniu (ponizej, pct<1).
					end
					unitList[#unitList + 1] = { pid = pid, pos = towerWorldPos(plot, pl.unitId, pl.x, pl.z), maxHp = maxHp, def = u.def or 0 }
				end
			end
			for pid in pairs(uhp) do -- prune HP jednostek usunietych przez gracza
				if placements[pid] == nil then uhp[pid] = nil end
			end
			if #unitList > 0 then
				for _, e in pairs(enemies) do
					local et = GameConfig.Wave.enemyTypes[e.typeId]
					if et and et.atkDmg then
						e.unitTimer = (e.unitTimer or 0) - dt
						if e.unitTimer <= 0 then
							local epos = enemyWorldPos(plot, e.pathT, e.lane, e.fwd)
							local best, bestD = nil, (et.atkRange or 14) * (et.atkRange or 14)
							for _, ui in ipairs(unitList) do
								if uhp[ui.pid] then
									local dx, dz = ui.pos.X - epos.X, ui.pos.Z - epos.Z
									local d2 = dx * dx + dz * dz
									if d2 <= bestD then bestD = d2; best = ui end
								end
							end
							if best then
								e.unitTimer = 1 / (et.atkRate or 1)
								-- DEF: pancerz REDUKUJE obrazenia, ale NIGDY do zera. Wrog ZAWSZE zdejmuje blokowi min
								-- defMinChipFrac*atkDmg -> zaden blok nie jest niezniszczalny, droga ZAWSZE sie w koncu utoruje.
								-- Wyzszy def/HP = blok trzyma DUZO dluzej (wolniej pada), ale w koncu padnie. e.atkDmg zamrozony na spawnie.
								local base = (e.atkDmg or et.atkDmg)
								local minChip = base * (GameConfig.Sim.defMinChipFrac or 0)
								local dealt = math.max(minChip, base - (best.def or 0))
								if dealt > 0 then
									uhp[best.pid] = uhp[best.pid] - dealt
									if uhp[best.pid] <= 0 then
										uhp[best.pid] = nil
										_unitHpSend[best.pid] = nil
										if _build then _build.KillUnit(player, best.pid) end
									elseif _unitHpNet then
										local last = _unitHpSend[best.pid]
										if not last or (os.clock() - last) >= 0.2 then
											_unitHpSend[best.pid] = os.clock()
											_unitHpNet:FireClient(player, { placementId = best.pid, hpPct = uhp[best.pid] / best.maxHp, hp = math.max(0, uhp[best.pid]), maxHp = best.maxHp })
										end
									end
								end
							end
						end
					end
				end
			end

			-- 3) atak rdzenia (wrog w zasiegu broni od rdzenia -> ostrzal na interwale, NIE wchodzi w rdzen)
			for _, e in pairs(enemies) do
				if e.atCore then
					e.coreTimer -= dt
					if e.coreTimer <= 0 then
						local et = GameConfig.Wave.enemyTypes[e.typeId]
						e.coreTimer = (et and et.coreAttackInterval) or 1
						CombatService.EnemyReachedCore:Fire(player, e.typeId)
					end
				end
			end

			-- 4) sync PER PLOT: CHUNKOWANY buffer (u16 id + u8 pathT + u8 hpPct = 4B/wrog, +2B naglowek/chunk).
			-- Chunkowanie bo UnreliableRemoteEvent dropuje CALY pakiet >~900B (kiedys ~225 wrogow na plocie =
			-- zamrozeni wrogowie na kliencie; w solo jeden plac niesie cala pule fali). buildSyncChunks sortuje
			-- po pathT (najblizsi rdzenia w chunk 0), tnie po ENEMIES_PER_PACKET, twardy cap MAX_SYNC_CHUNKS.
			-- Pruning idzie osobno przez reliable EnemyEvents -> chunk = niezalezna aktualizacja znanych wrogow.
			if _enemySync then
				local chunks, total, sent = buildSyncChunks(enemies)
				for _, buf in ipairs(chunks) do
					_enemySync:FireAllClients(plot.plotId, buf)
					_syncBytes += buffer.len(buf)
				end
				if sent < total then
					local now = os.clock()
					if now - _lastSyncOverflowWarn >= OVERRUN_WARN_EVERY then
						_lastSyncOverflowWarn = now
						warn(("[CombatService] EnemySync: %d wrogow > cap %d na plocie %d - nadwyzka niesynchronizowana"):format(total, ENEMIES_PER_PACKET * MAX_SYNC_CHUNKS, plot.plotId))
					end
				end
			end

			-- BossHP -> pasek bossa (rzadkie: <=1 boss/plot; reliable do wlasciciela plotu)
			if _bossHP then
				for _, e in pairs(enemies) do
					if e.isBoss then
						_bossHP:FireClient(player, { plotId = plot.plotId, hp = e.hp, maxHp = e.maxHp, name = e.bossName, big = e.isBigBoss })
					end
				end
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

-- FIX P0: nadganianie akumulatora z KLAMRA MAX_STEPS_PER_FRAME. Nadwyzka dlugu PORZUCANA (nie kolejkowana)
-- -> przy zadyszce serwer zwalnia symulacje zamiast wpadac w spirale smierci. Sub-tickowa reszta (_acc %
-- _dtStep) zachowana. Zwraca liczbe wykonanych krokow (do testu). Definicja PO step() (uzywa go jako upvalue).
local function advanceAccumulator(dt: number): number
	_acc += dt
	local steps = 0
	while _acc >= _dtStep and steps < MAX_STEPS_PER_FRAME do
		local t0 = os.clock()
		step(_dtStep)
		_lastStepMs = (os.clock() - t0) * 1000
		_acc -= _dtStep
		steps += 1
	end
	if _acc >= _dtStep then
		_acc = _acc % _dtStep -- PORZUC caly zalegly dlug, zostaw tylko reszte sub-tickowa
		local now = os.clock()
		if now - _lastOverrunWarn >= OVERRUN_WARN_EVERY then
			_lastOverrunWarn = now
			warn(("[CombatService] symulacja nie nadaza (>%d krokow/klatke, step=%.1fms) - porzucam dlug"):format(MAX_STEPS_PER_FRAME, _lastStepMs))
		end
	end
	return steps
end

-- gracz trafil wroga z broni FPS (WeaponsSystem onHit -> Net.PlayerHitEnemy). -playerShotDmg HP.
-- Gated: dziala TYLKO gdy wrog o tym id istnieje na plocie gracza (czyli w trakcie fali).
function CombatService.PlayerHitEnemy(player, id, isHead)
	if type(id) ~= "number" then return end
	local enemies = _enemies[player]
	local e = enemies and enemies[id]
	if not e then return end -- brak wroga (poza fala / zly id / juz martwy) -> ignoruj (anti-cheat lekki)
	-- dmg PER BRON: serwer patrzy jaki Tool gracz trzyma (WR_WaveWeapons: Pistol/AR/Shotgun/Sniper) i bierze
	-- dmg z SimConfig.playerWeaponDmg; brak wpisu / brak broni -> playerShotDmg. Server-authoritative (klient nie oszuka).
	local dmg = GameConfig.Sim.playerShotDmg or 10
	local perW = GameConfig.Sim.playerWeaponDmg
	if perW and typeof(player) == "Instance" and player.Character then
		local tool = player.Character:FindFirstChildOfClass("Tool")
		if tool and perW[tool.Name] then dmg = perW[tool.Name] end
	end
	if isHead then -- HEAD SHOT: bonus obrazen (echo "-N" tez wyzsze) + licznik do summary
		dmg = dmg * (GameConfig.Sim.headshotMult or 1)
		_playerHS[player] = (_playerHS[player] or 0) + 1
	end
	local eff = math.min(dmg, math.max(0, e.hp)) -- efektywne obrazenia (bez overkill)
	_runDamage[player] = (_runDamage[player] or 0) + eff
	_playerDmg[player] = (_playerDmg[player] or 0) + eff -- obrazenia GRACZA (bron FPS) do summary
	e.hp -= dmg
	-- liczba "-N" NAD wrogiem OD RAZU (exact dmg; niezaleznie od kwantyzacji hpPct w EnemySync -> dziala tez na tankach)
	if _playerShotHit then
		_playerShotHit:FireClient(player, e.plotId or 0, id, dmg, isHead) -- isHead -> klient pokaze popup HEAD SHOT
	end
	if e.hp <= 0 then
		enemies[id] = nil
		queueDeath(player, id)
		_playerKills[player] = (_playerKills[player] or 0) + 1 -- zabojstwa GRACZA (bron FPS) do summary
		CombatService.EnemyDied:Fire(player, e.typeId)
	end
end

-- AoE: zadaj `dmg` wszystkim wrogom gracza w promieniu `radius` (XZ) od `center`. Zwraca liczbe TRAFIONYCH.
-- Wspolna sciezka dla Explosive Ammo (splash) i strike'ow (konwoj/nalot/nuke): te same liczniki dmg/kille/EnemyDied.
-- Kille zbierane do listy i usuwane PO petli (nie mutujemy tabeli w trakcie wlasnego pairs).
function CombatService.AreaDamage(player, center: Vector3, radius: number, dmg: number): number
	local enemies = _enemies[player]
	if not enemies or not dmg or dmg <= 0 then
		return 0
	end
	local plot = resolvePlot(player)
	if not plot then
		return 0
	end
	local r2 = radius * radius
	local hit = 0
	local kills = nil
	for _, e in pairs(enemies) do
		local epos = enemyWorldPos(plot, e.pathT, e.lane, e.fwd)
		local dx, dz = epos.X - center.X, epos.Z - center.Z
		if (dx * dx + dz * dz) <= r2 then
			_runDamage[player] = (_runDamage[player] or 0) + math.min(dmg, math.max(0, e.hp)) -- efektywne (bez overkill)
			e.hp -= dmg
			hit += 1
			if e.hp <= 0 then
				kills = kills or {}
				kills[#kills + 1] = e.id
			end
		end
	end
	if kills then
		for _, id in ipairs(kills) do
			local e = enemies[id]
			if e then
				enemies[id] = nil
				queueDeath(player, id)
				CombatService.EnemyDied:Fire(player, e.typeId)
			end
		end
	end
	return hit
end

-- Punkt celu strike'a: CENTROID zywych wrogow gracza w swiecie (nil gdy brak). Strike bije w skupisko.
function CombatService.PickStrikeTarget(player): Vector3?
	local enemies = _enemies[player]
	if not enemies then
		return nil
	end
	local plot = resolvePlot(player)
	if not plot then
		return nil
	end
	local sx, sy, sz, n = 0, 0, 0, 0
	for _, e in pairs(enemies) do
		local epos = enemyWorldPos(plot, e.pathT, e.lane, e.fwd)
		sx += epos.X; sy += epos.Y; sz += epos.Z; n += 1
	end
	if n == 0 then
		return nil
	end
	return Vector3.new(sx / n, sy / n, sz / n)
end

function CombatService.Init()
	CombatService.EnemyDied = Signal.new() -- (player, enemyTypeId)
	CombatService.EnemyReachedCore = Signal.new() -- (player, enemyTypeId)
end

function CombatService.Start()
	_plot = ServiceRegistry.get("PlotService")
	_stat = ServiceRegistry.get("StatProfileService")
	_grid = ServiceRegistry.get("GridService")
	_build = ServiceRegistry.get("BuildService")
	_level = ServiceRegistry.get("LevelService") -- lewelowanie TYPU (mnoznik dmg/hp) — odczyt per-krok, nie per-wieza
	_enemySync = Net.get("EnemySync")
	_enemyEvents = Net.get("EnemyEvents")
	_bossHP = Net.get("BossHP")
	_unitHpNet = Net.get("UnitHp")
	_playerShotHit = Net.get("PlayerShotHit")

	Net.get("PlayerHitEnemy").OnServerEvent:Connect(function(player, id, isHead)
		CombatService.PlayerHitEnemy(player, tonumber(id), isHead == true)
	end)

	RunService.Heartbeat:Connect(function(dt)
		advanceAccumulator(dt) -- klamra MAX_STEPS_PER_FRAME (anty-spirala smierci) — FIX P0
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
	if deps.build ~= nil then _build = deps.build end
	if deps.hpNet ~= nil then _unitHpNet = deps.hpNet end
end
function CombatService._GetUnitHpForTest(player)
	return _unitHp[player]
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
-- FIX P0 hooki testowe: klamra akumulatora, chunkowanie sync, throttle-tabela HP.
function CombatService._AdvanceAccumulatorForTest(dt)
	return advanceAccumulator(dt)
end
function CombatService._GetAccForTest()
	return _acc
end
function CombatService._ResetAccForTest()
	_acc = 0
end
function CombatService._BuildSyncChunksForTest(enemies)
	return buildSyncChunks(enemies)
end
function CombatService._GetUnitHpSendForTest()
	return _unitHpSend
end
function CombatService._SeedUnitHpForTest(player, pid, hp)
	_unitHp[player] = _unitHp[player] or {}
	_unitHp[player][pid] = hp
	_unitHpSend[pid] = os.clock() -- symuluj wpis throttle po oberwaniu jednostki
end
function CombatService._GetSyncConstsForTest()
	return { perPacket = ENEMIES_PER_PACKET, maxChunks = MAX_SYNC_CHUNKS, maxSteps = MAX_STEPS_PER_FRAME, dtStep = _dtStep }
end

return CombatService
