--!nonstrict
-- ServerScriptService/Services/IndexService.luau  (§3.13 + ETAP 2)
-- Kolekcja w 4 KATEGORIACH + permanentny bonus luck za % ukonczenia. Config-driven, serwer-autorytatywny.
-- ETAP 2: wpisy liczone PER (unitId, variant). 3 kategorie jednostek (regular/shiny/galaxy) +
--   zakladka Wrogowie (STUB — odkrywanie w etapie 5). Jedyny writer profile.index.
--
-- STRUKTURA profile.index (DECYZJA): plaskie klucze zlozone { [unitId.."#"..variant] = true }.
--   Powod: spojnosc z invKey (Inventory), trywialna migracja (stary { [unitId]=true } -> dopisz "#regular"),
--   idempotentny Discover = sprawdzenie jednego klucza. Kategoria jednostki = sufiks wariantu klucza.
--   Wrogowie: NIE trzymane w profile.index w tym etapie (etap 5 zdefiniuje ich schemat kluczy).
--
-- Bonus luck = NAJWYZSZY osiagniety prog (highest-reached) z LACZNEGO %ukonczenia (27 jedn. + wrogowie).
-- Petla: rolki -> Discover(unit, variant) -> IndexUpdated -> StatProfile.Recompute -> lepsze rolki.
-- deps: ProfileService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local IndexService = {}

local _profileService = nil
local _netIndexUpdated = nil -- cache remote (guard nil w tescie)

-- klucz wpisu = unitId .. "#" .. variant (variant domyslnie "regular")
local function indexKey(unitId: string, variant): string
	return unitId .. "#" .. (variant or "regular")
end

local function unitTypeCount(): number
	local n = 0
	for _ in pairs(GameConfig.Units) do
		n += 1
	end
	return n
end

local function enemyTypeCount(): number
	local n = 0
	for _ in pairs(GameConfig.Wave.enemyTypes) do
		n += 1
	end
	return n
end

-- Rozklad odkrytych kluczy na warianty: { [variant] = { [unitId]=true } }.
local function discoveredByVariant(data)
	local out = {}
	if data and data.index then
		for k in pairs(data.index) do
			local parts = string.split(k, "#")
			local uid = parts[1]
			local var = parts[2]
			if var == nil or var == "" then
				var = "regular"
			end
			out[var] = out[var] or {}
			out[var][uid] = true
		end
	end
	return out
end

-- Stan per kategoria (§3.13 ETAP 2). Zwraca (categories[], overallCount, overallTotal, overallPercent).
local function computeCategories(data)
	local byVar = discoveredByVariant(data)
	local unitTotal = unitTypeCount()
	local enemyTotal = enemyTypeCount()

	local cats = {}
	local overallCount, overallTotal = 0, 0
	for _, c in ipairs(GameConfig.Index.categories) do
		local discovered, count, total = {}, 0, 0
		if c.kind == "unit" then
			total = unitTotal
			local set = byVar[c.variant] or {}
			for uid in pairs(set) do
				discovered[uid] = true
				count += 1
			end
		else -- enemy: STUB w tym etapie (brak odkrywania)
			total = enemyTotal
		end
		local percent = total > 0 and (count / total * 100) or 0
		cats[#cats + 1] = {
			id = c.id, label = c.label, kind = c.kind, variant = c.variant,
			discovered = discovered, count = count, total = total, percent = percent,
		}
		overallCount += count
		overallTotal += total
	end
	local overallPercent = overallTotal > 0 and (overallCount / overallTotal * 100) or 0
	return cats, overallCount, overallTotal, overallPercent
end

-- najwyzszy osiagniety prog (max luck wsrod progow pct <= percent)
local function luckForPercent(percent: number): number
	local best = 0
	for _, t in ipairs(GameConfig.Index.luckThresholds) do
		if percent >= t.pct and t.luck > best then
			best = t.luck
		end
	end
	return best
end

-- kategoria (id) do ktorej nalezy wariant jednostki (do payloadu IndexUpdated)
local function categoryForVariant(variant): string?
	for _, c in ipairs(GameConfig.Index.categories) do
		if c.kind == "unit" and c.variant == variant then
			return c.id
		end
	end
	return nil
end

-- MIGRACJA: stary indeks { [unitId]=true } (bez wariantu) -> potraktuj jako odkryty "regular".
-- Wykrycie starego klucza: brak "#" w kluczu.
local function migrateIndex(index)
	local rekey = {}
	for k in pairs(index) do
		if not string.find(k, "#", 1, true) then
			rekey[#rekey + 1] = k
		end
	end
	for _, oldK in ipairs(rekey) do
		index[indexKey(oldK, "regular")] = true
		index[oldK] = nil
	end
end

function IndexService.GetCompletion(player)
	local data = _profileService and _profileService.GetProfile(player)
	local cats, count, total, percent = computeCategories(data)
	return cats, count, total, percent
end

function IndexService.GetLuckBonus(player): number
	local data = _profileService and _profileService.GetProfile(player)
	local _, _, _, percent = computeCategories(data)
	return luckForPercent(percent)
end

-- Zapis odkrycia (idempotentny) dla pary (unitId, variant). true = nowy wpis.
-- Nowy wpis -> IndexUpdated (StatProfile.Recompute + klient).
function IndexService.Discover(player, unitId: string, variant): boolean
	local data = _profileService and _profileService.GetProfile(player)
	if not data then
		return false
	end
	variant = variant or "regular"
	local key = indexKey(unitId, variant)
	if data.index[key] then
		return false
	end
	data.index[key] = true
	local _, _, _, percent = computeCategories(data)
	local luckBonus = luckForPercent(percent)
	local category = categoryForVariant(variant)
	IndexService.IndexUpdated:Fire(player, unitId, variant, percent, luckBonus) -- serwer (StatProfile subskrybuje)
	if _netIndexUpdated then
		_netIndexUpdated:FireClient(player, {
			unitId = unitId, variant = variant, category = category,
			percent = percent, luckBonus = luckBonus,
		})
	end
	return true
end

function IndexService.Init()
	IndexService.IndexUpdated = Signal.new() -- (player, unitId, variant, percent, luckBonus)
end

function IndexService.Start()
	_profileService = ServiceRegistry.get("ProfileService")
	_netIndexUpdated = Net.get("IndexUpdated")

	-- migracja starego indeksu (unitId-only -> unitId#regular) przy zaladowaniu profilu
	_profileService.ProfileLoaded:Connect(function(player)
		local data = _profileService.GetProfile(player)
		if data and data.index then
			migrateIndex(data.index)
		end
	end)

	-- Net.GetIndexState (RF, C->S) -> stan poczatkowy UI kolekcji (per kategoria)
	Net.get("GetIndexState").OnServerInvoke = function(player)
		local data = _profileService.GetProfile(player)
		local cats, count, total, percent = computeCategories(data)
		return {
			categories = cats, -- [{id,label,kind,variant,discovered,count,total,percent}]
			overall = { count = count, total = total, percent = percent },
			luckBonus = luckForPercent(percent),
		}
	end
end

-- Hooki TYLKO do testow.
function IndexService._SetProfileServiceForTest(fake)
	_profileService = fake
end
function IndexService._MigrateForTest(index)
	migrateIndex(index)
end
function IndexService._KeyForTest(unitId, variant)
	return indexKey(unitId, variant)
end

return IndexService
