--!nonstrict
-- ServerScriptService/Services/DevService.luau
-- Panel deweloperski (gated): daje monety/kosci, resetuje skille/inventory/kolekcje/mnozniki, reset profilu.
-- Dostep: Studio ZAWSZE; w opublikowanej grze wlasciciel (game.CreatorId dla gry user-owned) + DEV_USER_IDS.
-- Klient wysyla intencje przez Net.DevAction (RF); serwer waliduje uprawnienia i wykonuje.
-- Mnozniki (luck/coinMult/dmg/...) wywodza sie ze `skills` + `index` (bonus luck) -> reset = wyczysc te.
-- deps: ProfileService, EconomyService, StatProfileService, InventoryService.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))

local DevService = {}

-- Dodaj tu swoje UserId zeby miec panel DEV w opublikowanej grze (grupa nie ma CreatorId==UserId).
local DEV_USER_IDS: { number } = {}

local _profile, _economy, _stat, _inv = nil, nil, nil, nil

local function isDev(player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	for _, id in ipairs(DEV_USER_IDS) do
		if player.UserId == id then
			return true
		end
	end
	return false
end

local function recompute(player)
	if _stat then
		_stat.Recompute(player)
	end
end

local function resetSkills(player, data)
	data.skills = {}
	recompute(player)
	Net.get("SkillTreeReset"):FireClient(player) -- klient czysci drzewko
end

local function resetIndex(player, data)
	data.index = {}
	recompute(player) -- odswiez luck (bonus z kolekcji)
end

local function resetInventory(player, data)
	data.inventory = {}
	if _inv then
		_inv.Changed:Fire(player) -- push InventorySync -> panel budowania
	end
end

-- action -> fn(player, data, amount)
local ACTIONS = {
	coins = function(player, data, amount)
		_economy.GrantCoins(player, amount or 10000)
	end,
	rolls = function(player, data, amount)
		data.spendableRolls += (amount or 100)
		_economy.SyncRolls(player)
	end,
	resetSkills = function(player, data)
		resetSkills(player, data)
	end,
	resetInventory = function(player, data)
		resetInventory(player, data)
	end,
	resetIndex = function(player, data)
		resetIndex(player, data)
	end,
	resetMultipliers = function(player, data)
		resetSkills(player, data)
		resetIndex(player, data)
	end,
	resetAll = function(player, data)
		data.coins = 0
		data.spendableRolls = 0
		data.skills = {}
		data.inventory = {}
		data.index = {}
		data.placements = {}
		data.pity = { sinceRare = 0 }
		data.waveNumber = 1
		data.serverLuckBuys = 0
		recompute(player)
		_economy.GrantCoins(player, 0) -- push salda 0
		_economy.SyncRolls(player)
		if _inv then
			_inv.Changed:Fire(player)
		end
		Net.get("SkillTreeReset"):FireClient(player)
	end,
}

function DevService.Init() end

function DevService.Start()
	_profile = ServiceRegistry.get("ProfileService")
	_economy = ServiceRegistry.get("EconomyService")
	_stat = ServiceRegistry.get("StatProfileService")
	_inv = ServiceRegistry.get("InventoryService")

	Net.get("DevAction").OnServerInvoke = function(player, payload)
		if not isDev(player) then
			return { ok = false, msg = "brak uprawnien DEV" }
		end
		if type(payload) ~= "table" then
			return { ok = false, msg = "zly payload" }
		end
		local fn = ACTIONS[payload.action]
		if not fn then
			return { ok = false, msg = "nieznana akcja: " .. tostring(payload.action) }
		end
		local data = _profile.GetProfile(player)
		if not data then
			return { ok = false, msg = "profil nie zaladowany" }
		end
		fn(player, data, tonumber(payload.amount))
		return { ok = true }
	end
end

-- Hook TYLKO do testow.
function DevService._IsDevForTest(player)
	return isDev(player)
end

return DevService
