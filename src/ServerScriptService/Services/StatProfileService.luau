--!nonstrict
-- ServerScriptService/Services/StatProfileService.luau
-- JEDYNE zrodlo staty (§3.2). Agreguje: bazy (StatBaseConfig) + ranki skilli (profile.skills)
-- + [POST-BRAMKA] gamepassy/aktywne boosty -> plaska tabela Stats. Cache per gracz, recompute na zdarzenie.
-- REGULA FRAMEWORKU: zaden inny serwis nie liczy staty sam. Roll bierze luck stad, Grid cellBudget,
-- Combat dmgMult, Core coreHP. W slice skille=0 -> Get zwraca czyste bazy.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

-- Komplet pol Stats (§3.2). Kolejnosc = kontrakt; kompletnosc pilnowana w tescie.
local STAT_FIELDS = {
	"luck", "rollSpeed", "mutChance", "cellBudget", "dmgMult",
	"fireRateMult", "rangeMult", "coreHP", "coinMult", "offlineRate",
}

local StatProfileService = {}

local _cache: { [Player]: any } = {}
local _profileService = nil

-- Swieza kopia baz z configu (nigdy nie mutujemy wspoldzielonej tabeli StatBaseConfig).
local function freshBase()
	local base = GameConfig.StatBase
	local out = {}
	for _, k in ipairs(STAT_FIELDS) do
		out[k] = base[k]
	end
	return out
end

-- Czysta agregacja: bazy + delty rankow skilli. profileData=nil lub skills puste -> same bazy.
local function compute(profileData)
	local stats = freshBase()
	local skills = profileData and profileData.skills
	if type(skills) == "table" then
		local nodes = GameConfig.Skill.nodes
		for nodeId, rank in pairs(skills) do
			local node = nodes[nodeId]
			if node and node.effect and type(rank) == "number" then
				local stat = node.effect.stat
				if stats[stat] ~= nil then
					stats[stat] = stats[stat] + node.effect.perRank * rank
				end
			end
		end
	end
	return stats
end

function StatProfileService.Init()
	StatProfileService.StatsChanged = Signal.new() -- (player, Stats)
end

function StatProfileService.Recompute(player: Player)
	local data = _profileService and _profileService.GetProfile(player) or nil
	local stats = compute(data)
	_cache[player] = stats
	if StatProfileService.StatsChanged then
		StatProfileService.StatsChanged:Fire(player, stats)
	end
	return stats
end

function StatProfileService.Get(player: Player)
	local cached = _cache[player]
	if cached == nil then
		cached = StatProfileService.Recompute(player)
	end
	return cached
end

function StatProfileService.Start()
	_profileService = ServiceRegistry.get("ProfileService")

	-- Recompute triggery dostepne w slice: ProfileLoaded.
	-- (SkillPurchased / zakup passa-boosta / wygasniecie boosta -> POST-BRAMKA.)
	_profileService.ProfileLoaded:Connect(function(player: Player)
		StatProfileService.Recompute(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		_cache[player] = nil
	end)

	-- Profile zaladowane zanim serwis wystartowal (load async).
	for _, player in ipairs(Players:GetPlayers()) do
		if _profileService.IsLoaded(player) then
			StatProfileService.Recompute(player)
		end
	end
end

-- Hook TYLKO do testow: policz bazy bez gracza/profilu (skille = 0).
function StatProfileService._ComputeBaseForTest()
	return compute(nil)
end
-- Hook TYLKO do testow: policz staty dla podanego profileData (bazy + delty skilli).
function StatProfileService._ComputeForTest(profileData)
	return compute(profileData)
end

return StatProfileService
