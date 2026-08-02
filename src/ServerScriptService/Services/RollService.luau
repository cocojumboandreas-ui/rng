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

local _stat, _inv, _index, _profile, _economy = nil, nil, nil, nil, nil
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

	-- 3) MUTACJA — KASKADA WSPINAJACA: wchodzisz od x2 w gore, kazdy szczebel wg step*mutChance.
	--    x2/x4 zawsze; wyzsze wg malejacego %. Stop na pierwszym nietrafionym; final = najwyzszy osiagniety.
	local mutation = nil
	local totalMult = 1 -- ILOCZYN zlapanych koniczyn (2 * 4 * 8 ...)
	for _, rung in ipairs(GameConfig.Mutation.ladder) do
		local p = math.clamp((rung.step or 0) * (stats.mutChance or 1), 0, 1)
		if rng:NextNumber() <= p then
			mutation = { id = rung.id, mult = rung.mult }
			totalMult *= rung.mult
		else
			break
		end
	end

	-- 4) WARIANT — osobny, niezalezny rzut (finish kolekcjonerski), od najrzadszego (galaxy -> shiny).
	-- v1: TYLKO wizual + kolekcja (zero wplywu na staty). Skalowany statem variantLuck.
	local variant = GameConfig.Variant.fallback or "regular"
	local vLuck = stats.variantLuck or 1
	for _, v in ipairs(GameConfig.Variant.ladder) do
		local vN = math.max(1, math.floor(v.chanceN / vLuck))
		if rng:NextInteger(1, vN) == 1 then
			variant = v.id
			break
		end
	end

	-- ilosc sztuk itema = ILOCZYN koniczyn * baza itemu(1). np. 2*4*8 = 64 szt. (tunowalne)
	local quantity = totalMult * 1
	return { unitId = chosen.id, rarityN = chosen.rarityN, mutation = mutation, variant = variant, totalMult = totalMult, quantity = quantity, pityTriggered = pityTriggered }
end

-- SELEKCJA itemu (rarity + wariant), BEZ mutacji — jedno ogniwo lancucha rolek.
local function selectOne(stats, pity, rng)
	local rarityCfg = GameConfig.Rarity
	local pool = unitsSorted()
	local pityTriggered = false
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
	local chosen = nil
	for _, u in ipairs(pool) do
		local nEff = math.max(1, math.floor(u.rarityN / stats.luck))
		if rng:NextInteger(1, nEff) == 1 then
			chosen = u
			break
		end
	end
	if not chosen then
		chosen = pool[#pool]
	end
	local variant = GameConfig.Variant.fallback or "regular"
	local vLuck = stats.variantLuck or 1
	for _, v in ipairs(GameConfig.Variant.ladder) do
		local vN = math.max(1, math.floor(v.chanceN / vLuck))
		if rng:NextInteger(1, vN) == 1 then
			variant = v.id
			break
		end
	end
	return { unitId = chosen.id, rarityN = chosen.rarityN, variant = variant, pityTriggered = pityTriggered }
end

-- DRABINA KONICZYN: ile szczebli zlapano (x2,x4 zwykle zawsze; wyzej wg step*mutChance).
-- To = ILE ROLEK zrobi lancuch: kazdy szczebel to jedno dodatkowe, prawdziwe losowanie (osobny item).
local function ladderDepth(stats, rng)
	local mutChance = stats.mutChance or 1
	local depth = 0
	for _, rung in ipairs(GameConfig.Mutation.ladder) do
		local p = math.clamp((rung.step or 0) * mutChance, 0, 1)
		if rng:NextNumber() <= p then
			depth += 1
		else
			break
		end
	end
	return depth
end

-- LANCUCH ROLEK (§3.4 + drabina): 1 klik -> N prawdziwych rolek po drabinie koniczyn.
-- x2 wypada -> nowy roll -> x4 -> nowy roll -> x8 ... az drabina sie urwie. KAZDY roll = OSOBNY item.
local function rollChain(player: Player)
	local data = _profile.GetProfile(player)
	if not data then
		return nil
	end
	local stats = _stat.Get(player)
	local rng = Random.new() -- serwerowy; NIGDY math.random

	local depth = ladderDepth(stats, rng)
	local nRolls = math.max(1, depth) -- min 1 (bazowy roll bez koniczyny); zwykle >=2 (x2,x4)
	local steps = {}
	local best = nil
	for i = 1, nRolls do
		local sel = selectOne(stats, data.pity, rng)
		-- KSIEGOWANIE per item (kolejnosc §3.4): Inventory.Add -> liczniki -> pity -> Index.Discover
		_inv.Add(player, sel.unitId, nil, sel.variant)
		data.lifetimeRolls += 1
		data.spendableRolls += 1
		if sel.rarityN >= GameConfig.Rarity.pity.guaranteeMinN then
			data.pity.sinceRare = 0
		else
			data.pity.sinceRare += 1
		end
		_index.Discover(player, sel.unitId, sel.variant)
		local mult = (i <= depth) and (2 ^ i) or nil -- koniczyna tego ogniwa (x2, x4, x8...)
		local step = { unitId = sel.unitId, rarityN = sel.rarityN, variant = sel.variant, mult = mult }
		steps[#steps + 1] = step
		if (not best) or sel.rarityN > best.rarityN then
			best = step
		end
		RollService.Rolled:Fire(player, { unitId = sel.unitId, rarityN = sel.rarityN, variant = sel.variant, mutation = mult and { mult = mult } or nil })
	end
	if _economy then
		_economy.SyncRolls(player) -- zdobyto spendableRolle -> zywe saldo do klienta
	end
	Net.get("RollResult"):FireClient(player, {
		unitId = best.unitId, rarityN = best.rarityN, variant = best.variant, -- reel packa pokazuje najlepszy pull
		chain = steps, -- pelny lancuch (kazdy element = osobny item + jego koniczyna)
		cloverTop = (depth > 0) and (2 ^ depth) or nil, -- szczyt kaskady koniczyn (nil = brak koniczyn)
		chainCount = nRolls,
	})
	return best
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
	rollChain(player)
end

-- Przyznanie rolek jako WALUTY (np. offline earn) — bez rolowania jednostek. RollService = writer spendableRolls.
function RollService.GrantRolls(player: Player, n: number): number
	n = math.floor(n or 0)
	if n <= 0 then
		return 0
	end
	local data = _profile and _profile.GetProfile(player)
	if not data then
		return 0
	end
	data.lifetimeRolls += n
	data.spendableRolls += n
	if _economy then
		_economy.SyncRolls(player)
	end
	return n
end

function RollService.Init()
	RollService.Rolled = Signal.new() -- (player, RollResult)
end

function RollService.Start()
	_stat = ServiceRegistry.get("StatProfileService")
	_inv = ServiceRegistry.get("InventoryService")
	_index = ServiceRegistry.get("IndexService")
	_profile = ServiceRegistry.get("ProfileService")
	_economy = ServiceRegistry.get("EconomyService")

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
