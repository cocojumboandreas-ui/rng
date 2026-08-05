--!nonstrict
-- ServerScriptService/Services/RollService.luau  (§3.4 + algorytm §6)
-- Rolka (dzielenie mianownikow, model Sol's), pity, mutacja, liczniki, payload rewealu.
-- Serwer-autorytatywny: klient wysyla tylko intencje (RollRequest); wynik/dmg/waluta liczy serwer.
-- Cooldown z Stats.rollSpeed egzekwowany serwerowo (klientowa animacja to teatr).
-- deps: StatProfileService, InventoryService, IndexService, ProfileService.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
local _special: { [any]: any } = {} -- player -> {gold,diamond,rainbow} liczniki specjalnych rolek
local _autoAcc: { [any]: any } = {} -- player -> {roll, regen} akumulatory Auto Roll (n2)

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
local function selectOne(stats, pity, rng, luckMult)
	local rarityCfg = GameConfig.Rarity
	local pool = unitsSorted()
	local pityTriggered = false
	local luck = stats.luck * (luckMult or 1) -- Gold/Diamond/Rainbow: chwilowy boost luck TEJ rolki
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
		local nEff = math.max(1, math.floor(u.rarityN / luck))
		if rng:NextInteger(1, nEff) == 1 then
			chosen = u
			break
		end
	end
	if not chosen then
		chosen = pool[#pool]
	end
	-- BONUS: szansa na ULEPSZENIE do rzadszego itemu (wiekszy tier). pool sortowany najrzadszy->najczestszy (idx 1 = rzadszy).
	local bonus = stats.bonusChance or 0
	if bonus > 0 and rng:NextNumber() < bonus then
		for i, u in ipairs(pool) do
			if u.id == chosen.id then
				if i > 1 then
					chosen = pool[i - 1]
				end
				break
			end
		end
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
	local cap = stats.cloverMaxTier or #GameConfig.Mutation.ladder -- sufit: x16/x32/x64 podnosza (domyslnie x8)
	local depth = 0
	for i, rung in ipairs(GameConfig.Mutation.ladder) do
		if i > cap then
			break
		end
		local p = math.clamp((rung.step or 0) * mutChance, 0, 1)
		if rng:NextNumber() <= p then
			depth += 1
		else
			break
		end
	end
	return depth
end

-- GOLD/DIAMOND/RAINBOW: OSOBNE liczniki per typ. Co N rolek (min N wsrod POSIADANYCH wezlow typu) jedna rolka
-- dostaje x{mult} luck. Typy niezalezne; gdy kilka trafi te sama rolke -> najwyzszy mult. Zwraca (luckMult, typ|nil).
local function specialRollBoost(player, data)
	local cfg = GameConfig.SkillEffect and GameConfig.SkillEffect.specialRolls
	if not cfg or type(data.skills) ~= "table" then
		return 1, nil
	end
	local skills = data.skills
	local counters = _special[player]
	if not counters then
		counters = {}
		_special[player] = counters
	end
	local bestMult, bestType = 1, nil
	for typeName, tcfg in pairs(cfg) do
		local minN = nil
		for nodeId, everyN in pairs(tcfg.everyByNode or {}) do
			if (skills[nodeId] or 0) > 0 and (not minN or everyN < minN) then
				minN = everyN
			end
		end
		if minN then
			local c = (counters[typeName] or 0) + 1
			if c >= minN then
				c = 0
				if (tcfg.mult or 1) > bestMult then
					bestMult = tcfg.mult
					bestType = typeName
				end
			end
			counters[typeName] = c
		end
	end
	return bestMult, bestType
end

-- ROLKA + DRABINA KONICZYN (§3.4): 1 klik -> 1 wylosowany item, a ILOCZYN zlapanych koniczyn
-- (x2*x4*x8...) = ILE SZTUK tego itemu trafia do inventory. Koniczyny to kolumny Bonus w reelu.
local function rollChain(player: Player, isAuto)
	local data = _profile.GetProfile(player)
	if not data then
		return nil
	end
	local stats = _stat.Get(player)
	local rng = Random.new() -- serwerowy; NIGDY math.random

	-- 1) DRABINA: ile koniczyn zlapano; ILOSC SZTUK = MAX koniczyna (najwyzsza), NIE iloczyn.
	local depth = ladderDepth(stats, rng)
	local clovers = {}
	for i = 1, depth do
		clovers[i] = { mult = 2 ^ i } -- x2, x4, x8, x16, x32, x64...
	end
	local totalMult = (depth > 0) and math.floor(2 ^ depth) or 1 -- np. drabina do x32 -> 32 sztuki

	-- 2) JEDEN wylosowany item (+ Gold/Diamond/Rainbow: osobne liczniki -> chwilowy boost luck co N rolek)
	local luckMult, special = specialRollBoost(player, data)
	local sel = selectOne(stats, data.pity, rng, luckMult)

	-- 3) KSIEGOWANIE (§3.4): totalMult SZTUK itemu -> Inventory; liczniki/pity/index raz
	_inv.Add(player, sel.unitId, nil, sel.variant, totalMult)
	data.lifetimeRolls += 1
	if not isAuto then
		data.spendableRolls += 1 -- reczna rolka NALICZA walute; auto-rolka ja ZUZYWA (odjete w petli auto)
	end
	if sel.rarityN >= GameConfig.Rarity.pity.guaranteeMinN then
		data.pity.sinceRare = 0
	else
		data.pity.sinceRare += 1
	end
	_index.Discover(player, sel.unitId, sel.variant)
	if _economy then
		_economy.SyncRolls(player) -- zywe saldo do klienta
	end

	RollService.Rolled:Fire(player, { unitId = sel.unitId, rarityN = sel.rarityN, variant = sel.variant, mutation = (depth > 0) and { mult = 2 ^ depth } or nil, quantity = totalMult })
	Net.get("RollResult"):FireClient(player, {
		unitId = sel.unitId, rarityN = sel.rarityN, variant = sel.variant,
		chain = clovers, -- kolumny koniczyn (Bonus) w reelu
		cloverTop = (depth > 0) and (2 ^ depth) or nil,
		quantity = totalMult, -- ile sztuk trafilo do inventory
		special = special, -- "gold"/"diamond"/"rainbow" gdy trafiona specjalna rolka (klient moze podkreslic)
		auto = isAuto or nil, -- true = auto-rolka (klient: KOMPAKTOWY reel na gorze, nie fullscreen)
	})
	return sel
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
		_special[player] = nil
		_autoAcc[player] = nil
	end)

	-- AUTO ROLL (skill n2): gdy posiadany -> pasywna REGENERACJA spendableRolls + auto-rolka co rollSpeed,
	-- ktora ZUZYWA rolke (regen >= zuzycie -> nigdy nie schodzi do 0). Reel na kliencie = tryb kompaktowy.
	RunService.Heartbeat:Connect(function(dt)
		local ar = GameConfig.SkillEffect and GameConfig.SkillEffect.autoRoll
		if not ar then
			return
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local data = _profile and _profile.GetProfile(player)
			if data and data.skills and (data.skills[ar.node] or 0) > 0 then
				local acc = _autoAcc[player]
				if not acc then
					acc = { roll = 0, regen = 0 }
					_autoAcc[player] = acc
				end
				-- pasywna regeneracja rolek (w nieskonczonosc)
				acc.regen += dt * (ar.regenPerSec or 0)
				if acc.regen >= 1 then
					local add = math.floor(acc.regen)
					acc.regen -= add
					data.spendableRolls = (data.spendableRolls or 0) + add
					if _economy then
						_economy.SyncRolls(player)
					end
				end
				-- auto-rolka co rollSpeed (zuzywa rolke)
				acc.roll += dt
				local cd = (_stat and _stat.Get(player).rollSpeed) or 4
				if acc.roll >= cd then
					acc.roll = 0
					if (data.spendableRolls or 0) >= (ar.cost or 1) then
						data.spendableRolls -= (ar.cost or 1)
						rollChain(player, true) -- auto-rolka: nie nalicza waluty, reel kompaktowy
					end
				end
			else
				_autoAcc[player] = nil
			end
		end
	end)
end

-- Hook TYLKO do testow: czysta selekcja+mutacja bez serwisow.
function RollService._ComputeRollForTest(stats, pity, rng)
	return computeRoll(stats, pity, rng)
end
-- Hook TYLKO do testow: krok licznika specjalnych rolek (gold/diamond/rainbow). Zwraca (luckMult, typ|nil).
function RollService._SpecialBoostForTest(player)
	return specialRollBoost(player, _profile.GetProfile(player))
end

return RollService
