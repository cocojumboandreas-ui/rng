--!nonstrict
-- ServerScriptService/Services/IndexService.luau  (§3.13)
-- Kolekcja jednostek + permanentny bonus luck za % ukonczenia. Config-driven, serwer-autorytatywny.
-- Indeks liczy TYPY (unitId), NIE mutacje. Jedyny writer profile.index.
-- Bonus luck = NAJWYZSZY osiagniety prog (highest-reached) z IndexConfig.luckThresholds.
-- Petla: rolki -> Discover -> IndexUpdated -> StatProfile.Recompute (dolicza GetLuckBonus) -> lepsze rolki.
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

-- total = liczba unikalnych typow jednostek z UnitsConfig (NIE hardcode)
local function totalTypes(): number
	local n = 0
	for _ in pairs(GameConfig.Units) do
		n += 1
	end
	return n
end

local function completion(data): (number, number, number)
	local total = totalTypes()
	local count = 0
	if data and data.index then
		for _ in pairs(data.index) do
			count += 1
		end
	end
	local percent = total > 0 and (count / total * 100) or 0
	return count, total, percent
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

function IndexService.GetCompletion(player)
	local data = _profileService and _profileService.GetProfile(player)
	return completion(data)
end

function IndexService.GetLuckBonus(player): number
	local data = _profileService and _profileService.GetProfile(player)
	local _, _, percent = completion(data)
	return luckForPercent(percent)
end

-- Zapis odkrycia (idempotentny). true = nowy typ. Nowy typ -> IndexUpdated (StatProfile.Recompute + klient).
function IndexService.Discover(player, unitId: string): boolean
	local data = _profileService and _profileService.GetProfile(player)
	if not data then
		return false
	end
	if data.index[unitId] then
		return false
	end
	data.index[unitId] = true
	local _, _, percent = completion(data)
	local luckBonus = luckForPercent(percent)
	IndexService.IndexUpdated:Fire(player, unitId, percent, luckBonus) -- serwer (StatProfile subskrybuje)
	if _netIndexUpdated then
		_netIndexUpdated:FireClient(player, { unitId = unitId, percent = percent, luckBonus = luckBonus })
	end
	return true
end

function IndexService.Init()
	IndexService.IndexUpdated = Signal.new() -- (player, unitId, percent, luckBonus)
end

function IndexService.Start()
	_profileService = ServiceRegistry.get("ProfileService")
	_netIndexUpdated = Net.get("IndexUpdated")

	-- Net.GetIndexState (RF, C->S) -> stan poczatkowy UI kolekcji
	Net.get("GetIndexState").OnServerInvoke = function(player)
		local data = _profileService.GetProfile(player)
		local count, total, percent = completion(data)
		return {
			discovered = (data and data.index) or {}, -- { [unitId] = true }
			count = count,
			total = total,
			percent = percent,
			luckBonus = luckForPercent(percent),
		}
	end
end

-- Hooki TYLKO do testow.
function IndexService._SetProfileServiceForTest(fake)
	_profileService = fake
end

return IndexService
