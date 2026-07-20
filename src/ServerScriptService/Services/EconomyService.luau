--!nonstrict
-- ServerScriptService/Services/EconomyService.luau  (§3.11)
-- Monety: JEDYNY writer profile.coins. Nagrody (x Stats.coinMult), wydatki, nagroda za fale.
-- Offline earn = POST-BRAMKA (EconomyConfig.offline). deps: ProfileService, StatProfileService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local EconomyService = {}

local _profile, _stat = nil, nil
local _coinsSync = nil -- cache remote'a (guard: nil w edit-mode tescie)

function EconomyService.GetCoins(player): number
	local data = _profile and _profile.GetProfile(player)
	return data and data.coins or 0
end

local function pushBalance(player, balance)
	if _coinsSync then
		_coinsSync:FireClient(player, { balance = balance })
	end
	EconomyService.CoinsChanged:Fire(player, balance)
end

-- amount x Stats.coinMult; zwraca faktycznie dodane monety
function EconomyService.Award(player, amount: number, reason: string?): number
	local data = _profile and _profile.GetProfile(player)
	if not data then
		return 0
	end
	local mult = (_stat and _stat.Get(player).coinMult) or 1
	local gained = math.floor(amount * mult + 0.5)
	data.coins += gained
	pushBalance(player, data.coins)
	return gained
end

function EconomyService.TrySpend(player, amount: number): boolean
	local data = _profile and _profile.GetProfile(player)
	if not data or data.coins < amount then
		return false
	end
	data.coins -= amount
	pushBalance(player, data.coins)
	return true
end

-- Nagroda za czyszczenie fali: baza(waveNumber) z WaveConfig + kills*killReward, x coinMult (przez Award).
function EconomyService.AwardWave(player, waveNumber: number, kills: number): number
	local waves = GameConfig.Wave.waves
	local base
	if waves[waveNumber] and waves[waveNumber].coinReward then
		base = waves[waveNumber].coinReward
	else
		base = waves[1].coinReward * (GameConfig.Wave.scaling.coinGrowth ^ (waveNumber - 1))
	end
	local total = base + kills * GameConfig.Economy.killReward
	return EconomyService.Award(player, total, "wave")
end

function EconomyService.Init()
	EconomyService.CoinsChanged = Signal.new() -- (player, newBalance)
end

function EconomyService.Start()
	_profile = ServiceRegistry.get("ProfileService")
	_stat = ServiceRegistry.get("StatProfileService")
	_coinsSync = Net.get("CoinsSync")
	-- odswiez saldo klientowi po zaladowaniu profilu
	_profile.ProfileLoaded:Connect(function(player)
		pushBalance(player, EconomyService.GetCoins(player))
	end)
end

-- Hooki TYLKO do testow.
function EconomyService._InjectForTest(deps)
	_profile, _stat = deps.profile, deps.stat
end

return EconomyService
