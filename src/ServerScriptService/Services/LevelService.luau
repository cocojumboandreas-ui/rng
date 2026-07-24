--!nonstrict
-- ServerScriptService/Services/LevelService.luau  (Etap 3 indeksu — anty-sciana + coin sink)
-- LEWELOWANIE TYPU jednostki: level per unitId (wariant-niezalezny — regular/shiny/galaxy dziela poziom TYPU).
-- Poziom buffuje WSZYSTKIE postawione kopie typu (efekt czyta CombatService inline, bez per-tick call).
-- SERVER-AUTHORITATIVE coin sink: klient wysyla TYLKO intencje (LevelUpUnit); walidacja + spend tutaj.
-- JEDYNY writer profile.unitLevels. deps: ProfileService (unitLevels), EconomyService (TrySpend).
-- Config: LevelConfig (growthPerLevel/costGrowth/baseCostK/maxLevel) + UnitsConfig.rarityN. Zero liczb w logice.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local LevelService = {}

local _profile, _economy = nil, nil

local function cfg()
	return GameConfig.Level
end

-- baseCost(unitId) = floor(rarityN * baseCostK); rzadsze jednostki drozej lewelowac (proporcjonalne do rarityN).
local function baseCost(unitId: string): number
	local u = GameConfig.Units[unitId]
	local rarityN = (u and u.rarityN) or 1
	return math.floor(rarityN * cfg().baseCostK)
end

-- level TYPU (0 gdy brak profilu/pola). unitLevels[unitId] domyslnie nil -> 0.
function LevelService.GetLevel(player, unitId: string): number
	local data = _profile and _profile.GetProfile(player)
	local levels = data and data.unitLevels
	return (levels and levels[unitId]) or 0
end

-- Cala mapa poziomow gracza (do JEDNEGO odczytu per-krok w CombatService; mnoznik liczony inline tam).
-- Zwraca referencje do tabeli profilu (nie mutowac poza LevelService) albo pusta gdy brak.
function LevelService.GetLevels(player)
	local data = _profile and _profile.GetProfile(player)
	return (data and data.unitLevels) or {}
end

-- Koszt przejscia z `level` na `level+1` = baseCost(unitId) * costGrowth^level (geometryczny wzrost).
function LevelService.GetCost(unitId: string, level: number): number
	return math.floor(baseCost(unitId) * (cfg().costGrowth ^ level))
end

-- Mnoznik efektu dla aktualnego poziomu typu: growthPerLevel^level (MULTIPLIKATYWNY; level 0 -> 1.0).
function LevelService.GetLevelMult(player, unitId: string): number
	return cfg().growthPerLevel ^ LevelService.GetLevel(player, unitId)
end

-- Intencja gracza: kup +1 poziom TYPU. Walidacja server-side, koszt pobiera EconomyService.TrySpend.
-- Zwraca (ok: bool, newLevel?: number, reason?: string). reason: UnknownUnit|NoProfile|MaxLevel|NotEnoughCoins.
function LevelService.TryLevelUp(player, unitId: string)
	if GameConfig.Units[unitId] == nil then
		return false, nil, "UnknownUnit"
	end
	local data = _profile and _profile.GetProfile(player)
	if not data then
		return false, nil, "NoProfile"
	end
	local levels = data.unitLevels
	if levels == nil then -- twardy guard (Reconcile powinien dolac, ale nie zakladamy)
		levels = {}
		data.unitLevels = levels
	end
	local level = levels[unitId] or 0
	if level >= cfg().maxLevel then
		return false, level, "MaxLevel"
	end
	local cost = LevelService.GetCost(unitId, level)
	if not (_economy and _economy.TrySpend(player, cost)) then
		return false, level, "NotEnoughCoins"
	end
	local newLevel = level + 1
	levels[unitId] = newLevel -- JEDYNY zapis profile.unitLevels
	if LevelService.UnitLeveled then
		LevelService.UnitLeveled:Fire(player, unitId, newLevel)
	end
	return true, newLevel, nil
end

function LevelService.Init()
	LevelService.UnitLeveled = Signal.new() -- (player, unitId, newLevel)
end

function LevelService.Start()
	_profile = ServiceRegistry.get("ProfileService")
	_economy = ServiceRegistry.get("EconomyService")

	-- INTENCJA klienta (RemoteFunction): kup poziom. Serwer autorytatywny.
	Net.get("LevelUpUnit").OnServerInvoke = function(player, unitId)
		if type(unitId) ~= "string" then
			return { ok = false, reason = "BadArg" }
		end
		local ok, newLevel, reason = LevelService.TryLevelUp(player, unitId)
		return { ok = ok, newLevel = newLevel, reason = reason }
	end

	-- Stan poczatkowy panelu lewelowania (klient dostaje aktualne poziomy; przy zmianie odczytuje newLevel z RF).
	Net.get("GetUnitLevels").OnServerInvoke = function(player)
		return LevelService.GetLevels(player) -- kopia zbedna: RemoteFunction i tak kopiuje tabele na granicy
	end
end

-- Hooki TYLKO do testow (wstrzykniecie fake profile/economy bez ServiceRegistry).
function LevelService._InjectForTest(deps)
	if deps.profile ~= nil then
		_profile = deps.profile
	end
	if deps.economy ~= nil then
		_economy = deps.economy
	end
end

return LevelService
