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
local _waveProgress, _waveEnded, _bossDefeated, _runSummary = nil, nil, nil, nil
local _phase: { [any]: string } = {} -- player -> RunPhase (domyslnie Building)
local _run: { [any]: any } = {} -- player -> {kills, pool} podczas WaveActive
local _runStats: { [any]: any } = {} -- player -> {maxWave, coins} — akumulatory RUNU (przez wiele fal, do podsumowania)
local _runGen: { [any]: number } = {} -- player -> licznik runu; bump w finishRun ubija zalegly auto-start fali

local function isBossWave(waveNumber: number): boolean
	local bw = GameConfig.Wave.bossWave
	return waveNumber > 0 and bw ~= nil and bw > 0 and (waveNumber % bw == 0)
end

-- ── tiery wrogow (dane w WaveConfig; tu sam WZOR wyboru) ────────────────────────
-- najwyzszy odblokowany tier dla fali n. PRZEWIAZANE do fal bossow (co bossWave=20):
-- tier startowy = tierBase (3) na falach 1-19; +1 po KAZDEJ fali bossa (20->4, 40->5, 60->6...),
-- clamp do #tierTypes. Tak boss danej fali = najwyzszy nowy tier, a od nastepnej fali lata normalnie.
local function maxTierFor(waveNumber: number): number
	local bw = GameConfig.Wave.bossWave or 20
	local base = GameConfig.Wave.tierBase or 3
	local nTiers = #GameConfig.Wave.tierTypes
	return math.clamp(base + math.floor(waveNumber / bw), 1, nTiers)
end

-- deterministyczny wybor wariantu wroga w tierze (salt = numer fali -> stabilne, ale zmienne miedzy falami)
local function pickTierType(tier: number, salt: number): string
	local list = GameConfig.Wave.tierTypes[tier]
	if not list or #list == 0 then
		return "grunt"
	end
	return list[(salt % #list) + 1]
end

-- boss dla boss-fali: k = n/bossWave (1,2,3...) -> bossTiers[k] (coraz wiekszy, k>#-> ostatni)
local function bossTypeFor(waveNumber: number): string
	local bosses = GameConfig.Wave.bossTiers or { "boss" }
	local bw = GameConfig.Wave.bossWave or 20
	local k = math.max(1, math.floor(waveNumber / math.max(bw, 1)))
	return bosses[math.clamp(k, 1, #bosses)]
end

-- HP najsilniejszego ZWYKLEGO (nie-boss) wroga aktywnego na fali w — baza skalowania bossa.
-- boss fali 20 = bossHpVsPrevSoldier x (ten HP dla fali 19).
local function referenceSoldierHp(waveNumber: number): number
	if waveNumber < 1 then waveNumber = 1 end
	local maxTier = maxTierFor(waveNumber)
	local window = GameConfig.Wave.tierWindow or 3
	local lowTier = math.max(1, maxTier - window + 1)
	local maxBase = 0
	for tr = lowTier, maxTier do
		for _, typeId in ipairs(GameConfig.Wave.tierTypes[tr] or {}) do
			local et = GameConfig.Wave.enemyTypes[typeId]
			if et and not et.isBoss and (et.hp or 0) > maxBase then
				maxBase = et.hp
			end
		end
	end
	if maxBase <= 0 then maxBase = 30 end
	local hpMult = (GameConfig.Wave.scaling.hpGrowth or 1) ^ (waveNumber - 1)
	return maxBase * hpMult
end

-- PROTOTYP "mniej grubszych": podziel liczby wrogow przez proto.countDiv (kopia, NIE mutuje configu).
-- Zwraca nowy comp + przeliczony pool. countDiv=1 => bez zmian (oryginalny roj).
local function applyProto(comp)
	local div = (GameConfig.Wave.proto and GameConfig.Wave.proto.countDiv) or 1
	local out, pool = {}, 0
	for _, e in ipairs(comp) do
		local cnt = e[2]
		if div > 1 then cnt = math.max(1, math.floor(cnt / div + 0.5)) end
		out[#out + 1] = { e[1], cnt, e[3] }
		pool += cnt
	end
	return out, pool
end

-- sklad fali z WaveConfig(waveNumber): zwraca (composition {{typeId,count[,hpOverride]}}, poolSize, formation)
local function waveComposition(waveNumber: number)
	-- boss-fala: 1 boss (HP = 5x zolnierz z fali n-1) + podklad wrogow (tier maxTier-1)
	if isBossWave(waveNumber) then
		local grunts = GameConfig.Wave.bossGrunts or 0
		local mult = GameConfig.Wave.bossHpVsPrevSoldier or 5
		local bossType = bossTypeFor(waveNumber)
		local bet = GameConfig.Wave.enemyTypes[bossType]
		-- HP bossa = mult * najsilniejszy zwykly wrog fali n-1 * per-boss hpMult (SZARZA=mniej, by byla ubijalna)
		local bossHp = mult * referenceSoldierHp(waveNumber - 1) * ((bet and bet.hpMult) or 1)
		local comp = { { bossType, 1, bossHp } }
		if grunts > 0 then
			local backTier = math.max(1, maxTierFor(waveNumber) - 1)
			comp[#comp + 1] = { pickTierType(backTier, waveNumber), grunts }
		end
		local sc, pool = applyProto(comp) -- proto: mniej wrogow (boss zawsze zostaje bo min 1)
		return sc, pool, { cols = 6 }
	end
	-- jawna fala (np. [1]) — bez zmian
	local w = GameConfig.Wave.waves[waveNumber]
	if w then
		local pool = 0
		for _, e in ipairs(w.composition) do
			pool += e[2]
		end
		local sc, scPool = applyProto(w.composition) -- proto: mniej wrogow (kopia, nie mutuje configu)
		return sc, scPool, w.formation
	end
	-- generowana wzorem: FODDER FLOOR (staly udzial najnizszych tierow) + reszta na tiery okna z ODWROCONYMI
	-- wagami (nizszy tier = wieksza waga). Efekt: roj taniego miesa + rzadkie elity = tekstura TD. Fodder floor
	-- dziala NIEZALEZNIE od okna top-N, wiec na falach 60+ (okno tier 3-6) roj tieru 1-2 dalej istnieje.
	local s = GameConfig.Wave.scaling
	local pool = math.floor(s.poolBase + waveNumber * s.poolPerWave)
	local maxTier = maxTierFor(waveNumber)
	local window = GameConfig.Wave.tierWindow or 3
	local lowTier = math.max(1, maxTier - window + 1)

	local comp = {}
	local function push(tier, salt, cnt)
		if cnt and cnt > 0 then
			comp[#comp + 1] = { pickTierType(tier, salt), cnt }
		end
	end

	-- 1) FODDER FLOOR: staly % puli na najnizsze tiery (roj miesa), niezaleznie od okna elit.
	local fodderTiers = GameConfig.Wave.fodderTiers or {}
	local fodderBudget = math.floor(pool * (GameConfig.Wave.fodderFrac or 0))
	local fodderUsed = 0
	if fodderBudget > 0 and #fodderTiers > 0 then
		for idx, tr in ipairs(fodderTiers) do
			local cnt
			if idx == #fodderTiers then
				cnt = fodderBudget - fodderUsed -- ostatni fodder-tier bierze reszte fodder-puli
			else
				cnt = math.floor(fodderBudget / #fodderTiers)
				fodderUsed += cnt
			end
			push(tr, waveNumber + tr, cnt)
		end
	end

	-- 2) ELITY: reszta puli na tiery okna z ODWROCONYMI wagami; NAJNIZSZY tier okna dominuje (bierze reszte).
	local elitePool = pool - fodderBudget
	local totalW = 0
	for tr = lowTier, maxTier do
		totalW += (maxTier - tr + 1) -- waga ODWROCONA: nizszy tier = wieksza waga
	end
	local eliteUsed = 0
	for tr = maxTier, lowTier + 1, -1 do -- wyzsze tiery floor-em (rzadkie elity)
		local cnt = math.floor(elitePool * (maxTier - tr + 1) / totalW)
		push(tr, waveNumber + tr, cnt)
		eliteUsed += cnt
	end
	push(lowTier, waveNumber + lowTier, elitePool - eliteUsed) -- najnizszy tier okna = reszta -> dominuje

	local sc, scPool = applyProto(comp) -- proto: mniej wrogow (kopia)
	return sc, scPool, { cols = 6 }
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

-- Rozpocznij fale wg data.waveNumber: spawn puli, faza WaveActive, reset rdzenia. BEZ bramki fazy —
-- wolane i przez StartWave (pierwsza fala runu z Building), i przez endWave (fale leca CIAGIEM, bez przerwy).
local function beginWave(player)
	local data = _profile and _profile.GetProfile(player)
	if not data then
		return
	end
	local waveNumber = data.waveNumber or 1
	local comp, pool = waveComposition(waveNumber)

	_phase[player] = Enums.RunPhase.WaveActive
	_run[player] = { kills = 0, pool = pool }
	-- BEZ resetu HP rdzenia co fale: HP przechodzi miedzy falami (fale leca ciagiem). Reset tylko na START RUNU (StartWave).
	for _, entry in ipairs(comp) do
		_combat.SpawnEnemies(player, waveNumber, { enemyTypeId = entry[1], count = entry[2], formation = { cols = 6 }, hpOverride = entry[3] })
	end
	WaveService.WaveStarted:Fire(player, waveNumber, pool)
	pushProgress(player, waveNumber, 0, pool)
end

-- Gracz klika "Rozpocznij fale" — TYLKO z fazy Building (start runu, przed pierwsza fala). Potem fale leca
-- ciagiem az do padu rdzenia / recznego "Zakoncz fale", bez okna budowania miedzy nimi.
function WaveService.StartWave(player)
	if WaveService.GetPhase(player) ~= Enums.RunPhase.Building then
		return -- tylko z Building (start runu)
	end
	_core.ResetHP(player) -- rdzen PELNY tylko na START RUNU; potem HP przechodzi miedzy falami (bez resetu co fale)
	beginWave(player)
end

-- KONIEC CALEGO RUNU (baza padla / gracz przerwal recznie): podsumowanie max fala + max dmg + monety.
-- Czyta obrazenia z CombatService PRZED ClearPlot (ClearPlot je zeruje), potem reset runu do fali 1.
local function finishRun(player, reason: string)
	_runGen[player] = (_runGen[player] or 0) + 1 -- uniewaznia zalegly auto-start fali (jesli StopWave trafil w okno miedzy falami)
	local data = _profile and _profile.GetProfile(player)
	local waveNumber = (data and data.waveNumber) or 1
	local rs = _runStats[player] or { maxWave = 0, coins = 0 }
	local maxWave = math.max(rs.maxWave or 0, waveNumber)
	local damage = (_combat and _combat.GetRunDamage and _combat.GetRunDamage(player)) or 0

	_combat.ClearPlot(player) -- czysci wrogow (i zeruje runDamage — dlatego czytamy damage wyzej)
	_core.ResetHP(player)
	if data then data.waveNumber = 1 end
	_phase[player] = Enums.RunPhase.Building
	_run[player] = nil
	_runStats[player] = nil

	local summary = { reason = reason, maxWave = maxWave, damage = math.floor(damage + 0.5), coins = math.floor((rs.coins or 0) + 0.5) }
	WaveService.WaveEnded:Fire(player, reason, summary)
	if _runSummary then
		_runSummary:FireClient(player, summary)
	end
end

-- KONIEC POJEDYNCZEJ FALI z wyczyszczeniem (Cleared) — run trwa dalej, akumuluje staty.
local function endWave(player, reason)
	if reason ~= Enums.WaveEndReason.Cleared then
		finishRun(player, "core") -- CoreDestroyed -> koniec runu z podsumowaniem
		return
	end
	local run = _run[player] or { kills = 0, pool = 0 }
	local data = _profile and _profile.GetProfile(player)
	local waveNumber = (data and data.waveNumber) or 1

	local coinsEarned = _economy.AwardWave(player, waveNumber, run.kills) -- boss-fala: x bossRewardMult (Economy)
	local rs = _runStats[player] or { maxWave = 0, coins = 0 }
	rs.coins = (rs.coins or 0) + coinsEarned
	rs.maxWave = math.max(rs.maxWave or 0, waveNumber)
	_runStats[player] = rs
	if isBossWave(waveNumber) then
		WaveService.BossDefeated:Fire(player, waveNumber)
		if _bossDefeated then
			_bossDefeated:FireClient(player, { plotId = plotIdOf(player), waveNumber = waveNumber })
		end
	end
	if data then
		data.waveNumber = waveNumber + 1
	end

	-- FALE CIAGIEM: NIE wracamy do fazy Building miedzy falami i NIE ma opoznienia. WaveEnded to tylko
	-- kosmetyka (konfetti + "+Monet" na kliencie); zaraz po nim startuje nastepna fala. Buduj jest
	-- niedostepny przez caly run (Building tylko przed 1. fala / po padzie rdzenia / po recznym stopie).
	local summary = { coinsEarned = coinsEarned, kills = run.kills, waveNumber = waveNumber }
	WaveService.WaveEnded:Fire(player, reason, summary)
	if _waveEnded then
		_waveEnded:FireClient(player, { plotId = plotIdOf(player), reason = reason, summary = summary })
	end
	beginWave(player) -- nastepna fala (n+1) NATYCHMIAST, zostajemy w WaveActive (zero przerwy, zero okna budowania)
end

-- Gracz konczy run RECZNIE (przycisk „Zakończ falę") — w dowolnej fazie -> podsumowanie.
function WaveService.StopWave(player)
	local phase = WaveService.GetPhase(player)
	if phase ~= Enums.RunPhase.WaveActive and phase ~= Enums.RunPhase.Building then
		return
	end
	finishRun(player, "stopped")
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

-- FIX P0: sprzatanie stanu per-gracz przy wyjsciu. Wczesniej _runGen NIE bylo zerowane (mikrowyciek:
-- integer + referencja-klucz Player zostawaly na zawsze). To JEDYNE 4 tabele kluczowane po graczu w tym pliku.
local function cleanupPlayer(player)
	_phase[player] = nil
	_run[player] = nil
	_runStats[player] = nil
	_runGen[player] = nil
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
	_runSummary = Net.get("RunSummary")

	Net.get("StartWave").OnServerEvent:Connect(function(player)
		WaveService.StartWave(player)
	end)
	Net.get("StopWave").OnServerEvent:Connect(function(player)
		WaveService.StopWave(player)
	end)
	_combat.EnemyDied:Connect(function(player)
		onEnemyDied(player)
	end)
	_core.CoreDestroyed:Connect(function(player)
		onCoreDestroyed(player)
	end)

	Players.PlayerRemoving:Connect(cleanupPlayer)
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
-- FIX P0 hooki testowe: zasianie/odczyt _runGen + wywolanie sprzatania (jak PlayerRemoving).
function WaveService._SeedRunGenForTest(player, v)
	_runGen[player] = v
end
function WaveService._GetRunGenForTest(player)
	return _runGen[player]
end
function WaveService._CleanupPlayerForTest(player)
	cleanupPlayer(player)
end

return WaveService
