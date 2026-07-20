--!nonstrict
-- ServerScriptService/Services/RollService.luau  (§3.4 + algorytm §6)
-- Rolka (dzielenie mianownikow, model Sol's), pity, mutacja, liczniki, payload rewealu.
-- Serwer-autorytatywny: klient wysyla tylko intencje (RollRequest); wynik/dmg/waluta liczy serwer.
-- Cooldown z Stats.rollSpeed egzekwowany serwerowo (klientowa animacja to teatr).
-- deps: StatProfileService, InventoryService, IndexService, ProfileService.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local RollService = {}

local _stat, _inv, _index, _profile = nil, nil, nil, nil
local _lastRoll: { [Player]: number } = {} -- player -> os.clock() ostatniej rolki

-- Jednostki posortowane MALEJACO po rarityN (najrzadsze pierwsze) — raz.
local _unitsSorted = nil
local function unitsSorted()
	if _unitsSorted then
		return _unitsSorted
	end
	local arr = {}
	for id, u in pairs(GameConfig.Units) do
		arr[#arr + 1] = { id = id, rarityN = u.rarityN }
	end
	table.sort(arr, function(a, b)
		return a.rarityN > b.rarityN
	end)
	_unitsSorted = arr
	return arr
end

-- PURE (§6 kroki 1-3): selekcja + mutacja, ZERO efektow ubocznych.
-- stats: {luck, mutChance}; pity: {sinceRare}; rng: Random. Zwraca payload §3.4.
local function computeRoll(stats, pity, rng)
	local rarityCfg = GameConfig.Rarity
	local pool = unitsSorted()
	local pityTriggered = false

	-- 1) PITY CHECK (przed selekcja)
	if pity and pity.sinceRare and pity.sinceRare >= rarityCfg.pity.threshold then
		local filt = {}
		for _, u in ipairs(pool) do
			if u.rarityN >= rarityCfg.pity.guaranteeMinN then
				filt[#filt + 1] = u
			end
		end
		if #filt > 0 then
			pool = filt
			pityTriggered = true
		end
	end

	-- 2) SELEKCJA — dzielenie mianownikow (od najrzadszej)
	local chosen = nil
	for _, u in ipairs(pool) do
		local nEff = math.max(1, math.floor(u.rarityN / stats.luck))
		if rng:NextInteger(1, nEff) == 1 then
			chosen = u
			break
		end
	end
	if not chosen then
		chosen = pool[#pool] -- FALLBACK = najmniejsze rarityN w puli
	end

	-- 3) MUTACJA — osobny, niezalezny rzut, od najrzadszej (x8 -> x4 -> x2)
	local mutation = nil
	local ladder = GameConfig.Mutation.ladder
	for i = #ladder, 1, -1 do
		local m = ladder[i]
		local mN = math.max(1, math.floor(m.chanceN / stats.mutChance))
		if rng:NextInteger(1, mN) == 1 then
			mutation = { id = m.id, mult = m.mult }
			break
		end
	end

	return { unitId = chosen.id, rarityN = chosen.rarityN, mutation = mutation, pityTriggered = pityTriggered }
end

-- Jedna rolka z efektami ubocznymi (kolejnosc §3.4).
local function rollOnce(player: Player)
	local data = _profile.GetProfile(player)
	if not data then
		return nil
	end
	local stats = _stat.Get(player)
	local rng = Random.new() -- serwerowy; NIGDY math.random

	local result = computeRoll(stats, data.pity, rng)

	-- 4) KSIEGOWANIE: wynik -> Inventory.Add -> liczniki -> pity -> Index.Discover -> Net
	_inv.Add(player, result.unitId, result.mutation)
	data.lifetimeRolls += 1
	data.spendableRolls += 1
	if result.rarityN >= GameConfig.Rarity.pity.guaranteeMinN then
		data.pity.sinceRare = 0
	else
		data.pity.sinceRare += 1
	end
	_index.Discover(player, result.unitId)

	RollService.Rolled:Fire(player, result)
	Net.get("RollResult"):FireClient(player, result)
	return result
end

-- Handler Net.RollRequest: walidacja profilu + cooldown.
function RollService.RequestRoll(player: Player)
	if not _profile.IsLoaded(player) then
		return
	end
	local stats = _stat.Get(player)
	local now = os.clock()
	local last = _lastRoll[player]
	if last and (now - last) < stats.rollSpeed then
		return -- cooldown; szybszy RollRequest odrzucony
	end
	_lastRoll[player] = now
	rollOnce(player)
end

function RollService.Init()
	RollService.Rolled = Signal.new() -- (player, RollResult)
end

function RollService.Start()
	_stat = ServiceRegistry.get("StatProfileService")
	_inv = ServiceRegistry.get("InventoryService")
	_index = ServiceRegistry.get("IndexService")
	_profile = ServiceRegistry.get("ProfileService")

	Net.get("RollRequest").OnServerEvent:Connect(function(player)
		RollService.RequestRoll(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		_lastRoll[player] = nil
	end)
end

-- Hook TYLKO do testow: czysta selekcja+mutacja bez serwisow.
function RollService._ComputeRollForTest(stats, pity, rng)
	return computeRoll(stats, pity, rng)
end

return RollService
