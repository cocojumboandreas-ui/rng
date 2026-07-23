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
	PlaceUnit = "RemoteFunction", -- C->S (itemId, cellX, cellZ) -> (ok, reason?)
	RemoveUnit = "RemoteFunction", -- C->S (placementId) -> (ok)
	StartWave = "RemoteEvent", -- C->S ()
	StopWave = "RemoteEvent", -- C->S () — gracz konczy run recznie -> podsumowanie
	WaveProgress = "RemoteEvent", -- S->C {plotId, waveNumber, killed, pool}
	WaveEnded = "RemoteEvent", -- S->C {plotId, reason, summary}
	RunSummary = "RemoteEvent", -- S->C {reason, maxWave, damage, coins} — koniec runu (baza padla / recznie)
	CoreHP = "RemoteEvent", -- S->C {plotId, hp, maxHp}
	BossHP = "RemoteEvent", -- S->C {plotId, hp, maxHp} (pasek HP bossa; odpalany gdy boss zyje)
	BossDefeated = "RemoteEvent", -- S->C {plotId, waveNumber} (flourish po pokonaniu bossa)
	EnemySync = "UnreliableRemoteEvent", -- S->C batch pozycji (sekcja 9)
	EnemyEvents = "RemoteEvent", -- S->C {plotId, spawns, deaths} — MUSI byc reliable
	StatsSync = "RemoteEvent", -- S->C pelny snapshot Stats
	CoinsSync = "RemoteEvent", -- S->C {balance}
	RollsSync = "RemoteEvent", -- S->C {spendableRolls} (blizniak CoinsSync — druga waluta, zywe saldo)
	SkillPurchase = "RemoteFunction", -- C->S (nodeId) -> {ok, reason?, rank?}
	GetSkillState = "RemoteFunction", -- C->S () -> {ranks, coins, spendableRolls} (stan poczatkowy UI)
	GetIndexState = "RemoteFunction", -- C->S () -> {categories[], overall{count,total,percent}, luckBonus} (§3.13, ETAP2)
	IndexUpdated = "RemoteEvent", -- S->C {unitId, variant, category, percent, luckBonus} (live wpis per-wariant)
	OfflineEarnings = "RemoteEvent", -- S->C {coins, seconds}
	UnitHp = "RemoteEvent", -- S->C {placementId, hpPct, hp, maxHp} (pasek HP jednostki: pct + liczby cur/max)
	UnitKilled = "RemoteEvent", -- S->C {placementId} (faza 5: jednostka zginela -> poof + zdejmij pasek)
	GetPlotInfo = "RemoteFunction", -- C->S () -> {plotId, gridOrigin(CFrame), width, depth, cellSize, faceDir} (tryb budowania)
	GetInventory = "RemoteFunction", -- C->S () -> { [invKey]=count } (poczatkowy stan panelu budowania)
	InventorySync = "RemoteEvent", -- S->C { [invKey]=count } (live liczby w panelu; push na Changed/ProfileLoaded)
	DevAction = "RemoteFunction", -- C->S {action, amount?} -> {ok, msg?} (panel DEV; serwer gated isDev)
	SkillTreeReset = "RemoteEvent", -- S->C () — DEV wyczyscil skille -> klient czysci drzewko
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
