--!nonstrict
-- ServerScriptService/Services/SkillService.luau  (§3.12)
-- Drzewko LEAN (3 galezie Roll/Base/Combat, pasywne ranki), zakupy w DWOCH walutach.
-- Serwer-autorytatywny: klient wysyla TYLKO intencje (SkillPurchase); pelna walidacja tu.
-- Kolejnosc zakupu: node istnieje -> rank<maxRank -> prereqi -> koszt w walucie wezla
--   (Coins->Economy.TrySpend | Rolls->profile.spendableRolls, NIGDY lifetimeRolls)
--   -> zapis ranku -> StatProfile.Recompute -> emit SkillPurchased.
-- deps: ProfileService, EconomyService, StatProfileService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local SkillService = {}

local _profile, _economy, _stat = nil, nil, nil

-- koszt zakupu rangi `targetRank` wezla: round(base * targetRank ^ costExp)
local function costFor(node, targetRank: number): number
	return math.round(node.base * targetRank ^ GameConfig.Skill.costExp)
end

-- prereqs (opcjonalne): { [nodeId] = minRank }. Brak w v1 LEAN — wsparcie na przyszlosc.
local function prereqsMet(skills, node): boolean
	if not node.prereqs then
		return true
	end
	for reqId, minRank in pairs(node.prereqs) do
		if (skills[reqId] or 0) < minRank then
			return false
		end
	end
	return true
end

function SkillService.GetRanks(player)
	local data = _profile and _profile.GetProfile(player)
	return (data and table.clone(data.skills)) or {}
end

-- Koszt nastepnej rangi (do UI). nil jesli max lub brak wezla.
function SkillService.GetNextCost(player, nodeId: string): number?
	local node = GameConfig.Skill.nodes[nodeId]
	if not node then
		return nil
	end
	local data = _profile and _profile.GetProfile(player)
	local cur = (data and data.skills[nodeId]) or 0
	if cur >= node.maxRank then
		return nil
	end
	return costFor(node, cur + 1)
end

-- (ok, reason?) reason: NoProfile|NoSuchNode|MaxRank|Prereq|NotEnough|BadCurrency
function SkillService.TryPurchase(player, nodeId: string)
	local data = _profile and _profile.GetProfile(player)
	if not data then
		return false, "NoProfile"
	end
	local node = GameConfig.Skill.nodes[nodeId]
	if not node then
		return false, "NoSuchNode"
	end
	local cur = data.skills[nodeId] or 0
	if cur >= node.maxRank then
		return false, "MaxRank"
	end
	if not prereqsMet(data.skills, node) then
		return false, "Prereq"
	end
	local targetRank = cur + 1
	local cost = costFor(node, targetRank)

	-- pobranie waluty (dopiero po walidacji reszty)
	if node.currency == Enums.Currency.Coins then
		if not _economy.TrySpend(player, cost) then
			return false, "NotEnough"
		end
	elseif node.currency == Enums.Currency.Rolls then
		if (data.spendableRolls or 0) < cost then
			return false, "NotEnough"
		end
		data.spendableRolls -= cost -- WALUTA; NIGDY lifetimeRolls
	else
		return false, "BadCurrency"
	end

	-- zapis ranku -> Recompute -> emit
	data.skills[nodeId] = targetRank
	if _stat then
		_stat.Recompute(player)
	end
	SkillService.SkillPurchased:Fire(player, nodeId, targetRank)
	return true
end

function SkillService.Init()
	SkillService.SkillPurchased = Signal.new() -- (player, nodeId, newRank)
end

function SkillService.Start()
	_profile = ServiceRegistry.get("ProfileService")
	_economy = ServiceRegistry.get("EconomyService")
	_stat = ServiceRegistry.get("StatProfileService")

	-- Net.SkillPurchase (RemoteFunction, C->S intencja) -> (ok, reason?) wg §8
	Net.get("SkillPurchase").OnServerInvoke = function(player, nodeId)
		if type(nodeId) ~= "string" then
			return { ok = false, reason = "BadArgs" }
		end
		local ok, reason = SkillService.TryPurchase(player, nodeId)
		return { ok = ok, reason = reason }
	end
end

-- Hooki TYLKO do testow.
function SkillService._InjectForTest(deps)
	_profile, _economy, _stat = deps.profile, deps.economy, deps.stat
end

return SkillService
