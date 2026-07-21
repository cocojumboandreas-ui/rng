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
local _rollsSync = nil -- cache remote'a RollsSync (druga waluta)
local _offlineRemote = nil -- cache remote'a OfflineEarnings

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
-- Broadcast salda spendableRolls (druga waluta). Economy = prezenter walut;
-- NIE jest writerem spendableRolls (pisza RollService +1 i SkillService -cost) — tylko czyta i syncuje.
function EconomyService.SyncRolls(player)
	if _rollsSync then
		local data = _profile and _profile.GetProfile(player)
		_rollsSync:FireClient(player, { spendableRolls = (data and data.spendableRolls) or 0 })
	end
end

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

-- ── OFFLINE EARN (§3.11) — FLAT RATE, tylko monety w v1 (offline spins = layer-2 gamepass) ──
-- PURE: raw monety (BEZ coinMult) + capped sekundy. Guardy klasycznych bugow offline:
--   first-login (offlineTs==0) -> 0 (NIE licz od epoki 1970); clock-skew (elapsed<0) -> 0; cap capHours.
local function computeOfflineRaw(offlineTs: number, now: number, offlineRate: number, capHours: number)
	if offlineTs == 0 then
		return 0, 0, true -- first-login -> brak zarobkow, tylko baseline
	end
	local elapsed = now - offlineTs
	if elapsed < 0 then
		elapsed = 0 -- clock skew
	end
	local capped = math.min(elapsed, capHours * 3600)
	local raw = (capped / 3600) * offlineRate
	return raw, capped, false
end

-- Liczone na ProfileLoaded. Przyznaje monety (Award -> coinMult RAZ) i zwraca {coins, seconds}.
-- Resetuje offlineTs=now (anti double-grant przy crash-rejoin + init first-login).
function EconomyService.ComputeOfflineEarnings(player)
	local data = _profile and _profile.GetProfile(player)
	if not data then
		return { coins = 0, seconds = 0 }
	end
	local now = os.time()
	local offlineRate = (_stat and _stat.Get(player).offlineRate) or 0
	local capHours = GameConfig.Economy.offline.capHours
	local raw, seconds, firstLogin = computeOfflineRaw(data.offlineTs or 0, now, offlineRate, capHours)
	data.offlineTs = now -- reset baseline (offlineTs znow ustawi ProfileReleasing przy leave)
	if firstLogin or raw <= 0 then
		return { coins = 0, seconds = seconds }
	end
	local gained = EconomyService.Award(player, raw, "offline") -- coinMult raz + CoinsSync
	return { coins = gained, seconds = seconds }
end

function EconomyService.Init()
	EconomyService.CoinsChanged = Signal.new() -- (player, newBalance)
	EconomyService.OfflineEarningsReady = Signal.new() -- (player, {coins, seconds})
end

function EconomyService.Start()
	_profile = ServiceRegistry.get("ProfileService")
	_stat = ServiceRegistry.get("StatProfileService")
	_coinsSync = Net.get("CoinsSync")
	_rollsSync = Net.get("RollsSync")
	_offlineRemote = Net.get("OfflineEarnings")
	-- po zaladowaniu profilu: salda + offline earn (popup gdy coins>0)
	_profile.ProfileLoaded:Connect(function(player)
		pushBalance(player, EconomyService.GetCoins(player))
		EconomyService.SyncRolls(player)
		local result = EconomyService.ComputeOfflineEarnings(player)
		if result.coins > 0 then
			EconomyService.OfflineEarningsReady:Fire(player, result)
			if _offlineRemote then
				_offlineRemote:FireClient(player, result)
			end
		end
	end)
end

-- Hooki TYLKO do testow.
function EconomyService._InjectForTest(deps)
	_profile, _stat = deps.profile, deps.stat
end
function EconomyService._ComputeOfflineRawForTest(offlineTs, now, offlineRate, capHours)
	return computeOfflineRaw(offlineTs, now, offlineRate, capHours)
end

return EconomyService
