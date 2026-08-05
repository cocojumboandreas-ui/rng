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
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

-- Komplet pol Stats (§3.2). Kolejnosc = kontrakt; kompletnosc pilnowana w tescie.
local STAT_FIELDS = {
	"luck", "rollSpeed", "mutChance", "cellBudget", "dmgMult",
	"fireRateMult", "rangeMult", "coreHP", "coinMult", "offlineRate", "variantLuck",
}

local StatProfileService = {}

local _cache: { [Player]: any } = {}
local _profileService = nil
local _index = nil -- IndexService (bonus luck z kolekcji)

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

-- mnoznik luck z DRZEWA umiejetnosci: bonusy (V-1) posiadanych wezlow Luck sie dodaja; brak = 1.0 (neutralny).
local function skillLuckMult(profileData)
	local skills = profileData and profileData.skills
	if type(skills) ~= "table" then
		return 1.0
	end
	local nodes = GameConfig.Skill.nodes
	local bonus = 0
	for nodeId, rank in pairs(skills) do
		local node = nodes[nodeId]
		if node and node.effect and node.effect.luckMult and type(rank) == "number" and rank > 0 then
			bonus += (node.effect.luckMult - 1)
		end
	end
	return 1 + bonus
end

-- EXPLOSIVE AMMO (galaz bojowa): szansa na splash = baseChance × mnoznik NAJWYZSZEGO posiadanego tieru (n78/n95-98).
-- 0 gdy nie posiadasz zadnego. CombatService czyta stats.explosiveChance przy trafieniu wiezy. Balans w SkillEffectConfig.
local function skillExplosiveChance(profileData): number
	local skills = profileData and profileData.skills
	local ex = GameConfig.SkillEffect and GameConfig.SkillEffect.explosive
	if type(skills) ~= "table" or not ex or not ex.tierMult then
		return 0
	end
	local best = 0
	for nodeId, rank in pairs(skills) do
		if type(rank) == "number" and rank > 0 then
			local m = ex.tierMult[nodeId]
			if m and m > best then
				best = m
			end
		end
	end
	return (best > 0) and ((ex.baseChance or 0) * best) or 0
end

-- SUFIT drabiny koniczyn: baseCloverTier + skille x16/x32/x64 (MutationConfig.tierUnlock). RollService klampuje depth.
local function skillCloverMaxTier(profileData): number
	local mc = GameConfig.Mutation
	local cap = (mc and mc.baseCloverTier) or #((mc and mc.ladder) or {})
	local skills = profileData and profileData.skills
	if type(skills) == "table" and mc and mc.tierUnlock then
		for nodeId, tier in pairs(mc.tierUnlock) do
			if (skills[nodeId] or 0) > 0 and tier > cap then
				cap = tier
			end
		end
	end
	return cap
end

-- BONUS: laczna szansa na ulepszenie itemu o tier (SkillEffectConfig.bonus.tierUpChance). Sumuje posiadane wezly.
local function skillBonusChance(profileData): number
	local skills = profileData and profileData.skills
	local b = GameConfig.SkillEffect and GameConfig.SkillEffect.bonus
	if type(skills) ~= "table" or not b or not b.tierUpChance then
		return 0
	end
	local acc = 0
	for nodeId, v in pairs(b.tierUpChance) do
		if (skills[nodeId] or 0) > 0 then
			acc += v
		end
	end
	return math.clamp(acc, 0, 1)
end

-- OFFLINE: mnoznik zarobkow offline z wezlow Offline Rolls (SkillEffectConfig.offline.mult). Sumuje posiadane.
local function skillOfflineMult(profileData): number
	local skills = profileData and profileData.skills
	local o = GameConfig.SkillEffect and GameConfig.SkillEffect.offline
	if type(skills) ~= "table" or not o or not o.mult then
		return 0
	end
	local acc = 0
	for nodeId, v in pairs(o.mult) do
		if (skills[nodeId] or 0) > 0 then
			acc += v
		end
	end
	return acc
end

function StatProfileService.Init()
	StatProfileService.StatsChanged = Signal.new() -- (player, Stats)
end

function StatProfileService.Recompute(player: Player)
	local data = _profileService and _profileService.GetProfile(player) or nil
	local stats = compute(data) -- baza + delty skilli (base luck = 1.0)
	do
		-- SZCZESCIE z DWOCH zrodel (decyzja): indeks (odebrane progi) i drzewo umiejetnosci (wezly Luck).
		-- total luck = baza × indeks × skille (mnoznikowo); rozbicie luckIndex/luckSkill do HUD (tooltip koniczyny).
		local indexBonus = (_index and _index.GetLuckBonus(player)) or 0
		stats.luckIndex = 1 + indexBonus
		stats.luckSkill = skillLuckMult(data)
		stats.luck = stats.luck * stats.luckIndex * stats.luckSkill
	end
	stats.explosiveChance = skillExplosiveChance(data) -- galaz bojowa: szansa splash (0 gdy brak Explosive Ammo)
	stats.cloverMaxTier = skillCloverMaxTier(data) -- sufit drabiny koniczyn (x16/x32/x64 podnosza)
	stats.bonusChance = skillBonusChance(data) -- Bonus: szansa na +1 tier itemu
	stats.offlineMult = skillOfflineMult(data) -- Offline Rolls: mnoznik zarobkow offline (monety+rolki)
	do
		local offCfg = GameConfig.SkillEffect and GameConfig.SkillEffect.offline
		local sk = data and data.skills
		stats.offlineRollsOn = (sk and offCfg and offCfg.unlockNode and (sk[offCfg.unlockNode] or 0) > 0) and true or false
	end
	stats.rollSpeed = math.max(3.0, stats.rollSpeed) -- floor: Fast Rolls schodzi max do 3.0s (start 4.0s)
	_cache[player] = stats
	if StatProfileService.StatsChanged then
		StatProfileService.StatsChanged:Fire(player, stats)
	end
	if typeof(player) == "Instance" then
		Net.get("StatsSync"):FireClient(player, stats) -- HUD: luck, offlineRate, cellBudget...
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
	_index = ServiceRegistry.get("IndexService")

	-- HUD moze pobrac aktualne staty (luck/rollSpeed + rozbicie) od razu, bez czekania na StatsSync.
	Net.get("GetStats").OnServerInvoke = function(player)
		return StatProfileService.Get(player)
	end

	-- Recompute triggery: ProfileLoaded + IndexUpdated (nowy typ w indeksie -> mogl zmienic prog luck).
	-- (SkillPurchase wola Recompute bezposrednio z SkillService; passy/boosty -> POST-BRAMKA.)
	_profileService.ProfileLoaded:Connect(function(player: Player)
		StatProfileService.Recompute(player)
	end)
	_index.IndexUpdated:Connect(function(player: Player)
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

-- Hook TYLKO do testow: szansa explosive dla podanego profileData (galaz bojowa).
function StatProfileService._SkillExplosiveChanceForTest(profileData)
	return skillExplosiveChance(profileData)
end
-- Hook TYLKO do testow: policz bazy bez gracza/profilu (skille = 0).
function StatProfileService._ComputeBaseForTest()
	return compute(nil)
end
-- Hook TYLKO do testow: policz staty dla podanego profileData (bazy + delty skilli, BEZ indeksu).
function StatProfileService._ComputeForTest(profileData)
	return compute(profileData)
end
-- Hook TYLKO do testow: wstrzyknij zaleznosci (profileService, index) do pelnego Recompute.
function StatProfileService._InjectForTest(deps)
	if deps.profileService ~= nil then
		_profileService = deps.profileService
	end
	if deps.index ~= nil then
		_index = deps.index
	end
end

return StatProfileService
