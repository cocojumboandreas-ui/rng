--!strict
-- Framework/Net.luau — JEDNO zrodlo nazw remote'ow (sekcja 8 architektury).
-- Server: tworzy instancje remote'ow w ReplicatedStorage.Net przy require.
-- Client: Net.get(name) czeka na zreplikowana instancje.
-- Serwis/kontroler NIGDY nie tworzy remote'ow recznie ani nie hardkoduje nazw.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "Net"

-- name -> ClassName. Kierunek/payload = w tabeli sekcji 8; tu tylko klasa instancji.
local REMOTES: { [string]: string } = {
	RollRequest = "RemoteEvent", -- C->S ()
	RollResult = "RemoteEvent", -- S->C {unitId, rarityN, revealTier, mutation?, pityTriggered}
	PlaceUnit = "RemoteFunction", -- C->S (itemId, cellX, cellZ, rot?) -> (ok, reason?) — rot = yaw stopnie (0/90/180/270), kosmetyka renderu
	RemoveUnit = "RemoteFunction", -- C->S (placementId) -> (ok)
	MoveUnit = "RemoteFunction", -- C->S (placementId, cellX, cellZ, rot?) -> (ok, reason?) — przenies juz postawiona jednostke (bez zwrotu do inventory)
	ClearPlot = "RemoteFunction", -- C->S () -> {ok, removed} — usun WSZYSTKIE jednostki gracza naraz (zwrot do inventory)
	StartWave = "RemoteEvent", -- C->S ()
	StopWave = "RemoteEvent", -- C->S () — gracz konczy run recznie -> podsumowanie
	PlayerHitEnemy = "RemoteEvent", -- C->S (enemyId) — gracz trafil wroga z broni FPS -> dmg per bron (tylko WaveActive)
	PlayerShotHit = "UnreliableRemoteEvent", -- S->C (plotId, enemyId, dmg) — echo trafienia: klient pokazuje "-N" nad wrogiem (exact dmg, cosmetyka)
	SetShootMode = "RemoteEvent", -- C->S (on:bool) — gracz wlacza/wylacza tryb strzelania (klawisz U, tylko w fali) -> daj/zabierz bronie
	WaveProgress = "RemoteEvent", -- S->C {plotId, waveNumber, killed, pool}
	WaveEnded = "RemoteEvent", -- S->C {plotId, reason, summary}
	RunSummary = "RemoteEvent", -- S->C {reason, maxWave, damage, coins} — koniec runu (baza padla / recznie)
	CoreHP = "RemoteEvent", -- S->C {plotId, hp, maxHp}
	BossHP = "RemoteEvent", -- S->C {plotId, hp, maxHp} (pasek HP bossa; odpalany gdy boss zyje)
	BossDefeated = "RemoteEvent", -- S->C {plotId, waveNumber} (flourish po pokonaniu bossa)
	EnemySync = "UnreliableRemoteEvent", -- S->C batch pozycji (sekcja 9)
	EnemyEvents = "RemoteEvent", -- S->C {plotId, spawns, deaths} — MUSI byc reliable
	StatsSync = "RemoteEvent", -- S->C pelny snapshot Stats
	GetStats = "RemoteFunction", -- C->S () -> Stats (HUD luck/rollSpeed + rozbicie luckIndex/luckSkill)
	CoinsSync = "RemoteEvent", -- S->C {balance}
	RollsSync = "RemoteEvent", -- S->C {spendableRolls} (blizniak CoinsSync — druga waluta, zywe saldo)
	GoldRollSync = "RemoteEvent", -- S->C {owned, remaining, everyN} — odliczanie do nastepnej zlotej rolki (skill Gold Rolls); klient chowa gdy owned=false
	GetGoldRollState = "RemoteFunction", -- C->S () -> {owned, remaining, everyN} — poczatkowy stan odliczania (PULL, unika race z pushem)
	SkillPurchase = "RemoteFunction", -- C->S (nodeId) -> {ok, reason?, rank?}
	GetSkillState = "RemoteFunction", -- C->S () -> {ranks, coins, spendableRolls, autoRollEnabled} (stan poczatkowy UI)
	SetAutoRollEnabled = "RemoteEvent", -- C->S (isEnabled:bool) — persystuj preferencje auto-roll ON/OFF w profilu
	GetIndexState = "RemoteFunction", -- C->S () -> {categories[], overall{count,total,percent}, luckBonus} (§3.13, ETAP2)
	IndexUpdated = "RemoteEvent", -- S->C {unitId, variant, category, percent, luckBonus} (live wpis per-wariant)
	ClaimIndexLuck = "RemoteFunction", -- C->S (pct) -> {ok, luckBonus?, reason?} — odbierz (claim) prog bonusu luck (ETAP 4)
	OfflineEarnings = "RemoteEvent", -- S->C {coins, rolls, seconds, drops={{unitId,qty,oddsN}}, doubleId} — podglad (niewydane do CLAIM)
	ClaimOffline = "RemoteFunction", -- C->S () -> {ok, coins?, items?, mult?} — odbierz oczekujace nagrody offline (CLAIM x1); X2 idzie przez DevProduct receipt
	GetIntroState = "RemoteFunction", -- C->S () -> {hasSeenIntro:boolean} (Faza 1B: cutscenka intro)
	MarkIntroSeen = "RemoteEvent", -- C->S () — gracz obejrzal/pominal intro -> ustaw hasSeenIntro=true w profilu
	UnitHp = "RemoteEvent", -- S->C {placementId, hpPct, hp, maxHp} (pasek HP jednostki: pct + liczby cur/max)
	UnitKilled = "RemoteEvent", -- S->C {placementId} (faza 5: jednostka zginela -> poof + zdejmij pasek)
	GetPlotInfo = "RemoteFunction", -- C->S () -> {plotId, gridOrigin(CFrame), width, depth, cellSize, faceDir} (tryb budowania)
	GetInventory = "RemoteFunction", -- C->S () -> { [invKey]=count } (poczatkowy stan panelu budowania)
	LevelUpUnit = "RemoteFunction", -- C->S (unitId) -> {ok, newLevel?, reason?} — kup +1 poziom TYPU jednostki (coin sink, Etap 3)
	GetUnitLevels = "RemoteFunction", -- C->S () -> { [unitId]=level } (stan poczatkowy panelu lewelowania)
	InventorySync = "RemoteEvent", -- S->C { [invKey]=count } (live liczby w panelu; push na Changed/ProfileLoaded)
	DevAction = "RemoteFunction", -- C->S {action, amount?} -> {ok, msg?} (panel DEV; serwer gated isDev)
	SkillTreeReset = "RemoteEvent", -- S->C () — DEV wyczyscil skille -> klient czysci drzewko
	WaveStrike = "RemoteEvent", -- S->C {kind, plotId, pos, radius} — strike galezi bojowej (konwoj/nalot/nuke) -> FX klienta
	SalvoResult = "RemoteEvent", -- S->C {kills} — podsumowanie salwy nalotu -> banner "×N" (nagroda za skutecznosc)
	AtomicStrike = "RemoteEvent", -- C->S () — gracz odpala ultimate ATOMOWKA (tymczasowy dev-przycisk)
	AtomicStrikeCue = "RemoteEvent", -- S->C {impactPos} — TYLKO do gracza ktory odpalil -> cutscenka klienta
	ConvoyStrike = "RemoteEvent", -- C->S () — gracz odpala KONWOJ (tymczasowy dev-przycisk)
	ConvoyCue = "RemoteEvent", -- S->C {linePos, lateralAxis, offsets, entryExitOffset, driveT, fireT, plotId} — TYLKO do gracza ktory odpalil -> animacja klienta (wjazd/postoj/wyjazd)
	IntroTeleportHome = "RemoteEvent", -- C->S () — gracz dotarl do finalu Kroku 5 (biala biel), prosi serwer o powrot na realny plac
	IntroTeleportHomeDone = "RemoteEvent", -- S->C () — TYLKO do gracza ktory poprosil, potwierdzenie ze PivotTo na realny plac zakonczony -> klient gasi flash
}

local Net = {}

local function ensureServerFolder(): Folder
	local f = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if f == nil then
		f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		f.Parent = ReplicatedStorage
	end
	return f :: Folder
end

-- Server: zbuduj wszystkie remote'y raz (idempotentnie).
if RunService:IsServer() then
	local folder = ensureServerFolder()
	for name, className in pairs(REMOTES) do
		local existing = folder:FindFirstChild(name)
		if existing ~= nil and existing.ClassName ~= className then
			existing:Destroy()
			existing = nil
		end
		if existing == nil then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
end

-- Zwraca instancje remote'a. Server: gotowa; Client: czeka na replikacje.
function Net.get(name: string): Instance
	assert(REMOTES[name] ~= nil, "Net: unknown remote '" .. tostring(name) .. "'")
	if RunService:IsServer() then
		return ensureServerFolder():WaitForChild(name)
	else
		local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
		return folder:WaitForChild(name)
	end
end

-- Lista zdefiniowanych nazw (do testow/diagnostyki).
function Net.list(): { string }
	local names = {}
	for name in pairs(REMOTES) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Net.classOf(name: string): string?
	return REMOTES[name]
end

return Net
