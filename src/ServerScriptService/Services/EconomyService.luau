--!nonstrict
-- ServerScriptService/Services/EconomyService.luau  (§3.11)
-- Monety: JEDYNY writer profile.coins. Nagrody (x Stats.coinMult), wydatki, nagroda za fale.
-- Offline earn = POST-BRAMKA (EconomyConfig.offline). deps: ProfileService, StatProfileService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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
local _roll = nil -- RollService (offline batch roll + grant przy CLAIM)
local _pending: { [any]: any } = {} -- player -> {coinsRaw, items, rolls} — NIEWYDANE nagrody offline (do CLAIM/CLAIM X2)

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

-- DEV: dodaj monety FLAT (bez coinMult) + push salda. Uzywane przez DevService.
function EconomyService.GrantCoins(player, amount: number)
	local data = _profile and _profile.GetProfile(player)
	if not data then
		return
	end
	data.coins += amount
	pushBalance(player, data.coins)
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
		_rollsSync:FireClient(player, {
			spendableRolls = (data and data.spendableRolls) or 0,
			lifetimeRolls = (data and data.lifetimeRolls) or 0, -- HUD: laczna liczba rolek nad nickiem
		})
	end
end

function EconomyService.AwardWave(player, waveNumber: number, kills: number): number
	local wc = GameConfig.Wave
	local base
	if wc.waves[waveNumber] and wc.waves[waveNumber].coinReward then
		base = wc.waves[waveNumber].coinReward
	else
		base = wc.waves[1].coinReward * (wc.scaling.coinGrowth ^ (waveNumber - 1))
	end
	if wc.bossWave and wc.bossWave > 0 and waveNumber % wc.bossWave == 0 then
		base = base * (wc.bossRewardMult or 1) -- boss-fala: wieksza nagroda
	end
	-- PROTOTYP "mniej grubszych": mniej killi => killReward x countDiv, zeby monety za fale sie zgadzaly
	local protoDiv = (GameConfig.Wave.proto and GameConfig.Wave.proto.countDiv) or 1
	local total = base + kills * GameConfig.Economy.killReward * protoDiv
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

-- Liczone na ProfileLoaded. CLAIM-GATED: NIC nie przyznaje od razu — liczy monety + rolluje offline-spiny
-- w jednostki (serwer, pure) i trzyma to jako PENDING; gracz odbiera przez CLAIM (x1) / CLAIM X2 (x2, 49R).
-- Zwraca PODGLAD do popupu: {coins(display), rolls, seconds, drops={{unitId,qty,oddsN}}, doubleId}.
function EconomyService.ComputeOfflineEarnings(player)
	local data = _profile and _profile.GetProfile(player)
	if not data then
		return { coins = 0, rolls = 0, seconds = 0, drops = {} }
	end
	local now = os.time()
	local st = _stat and _stat.Get(player)
	local offlineRate = (st and st.offlineRate) or 0
	local offlineMult = (st and st.offlineMult) or 0 -- Offline Rolls: mnoznik zarobkow offline (monety I rolki)
	local ocfg = GameConfig.Economy.offline
	local raw, seconds, firstLogin = computeOfflineRaw(data.offlineTs or 0, now, offlineRate, ocfg.capHours)
	raw = raw * (1 + offlineMult)
	data.offlineTs = now -- reset baseline (offlineTs znow ustawi ProfileReleasing przy leave)
	if firstLogin then
		_pending[player] = nil
		return { coins = 0, rolls = 0, seconds = seconds, drops = {} }
	end
	-- rolki offline = LICZBA spinow (tylko gdy odblokowane n3); realnie rolowane w jednostki
	local rollsRate = (ocfg.rollsPerHour or 0) * (1 + offlineMult)
	local rollsCount = (st and st.offlineRollsOn) and math.floor((seconds / 3600) * rollsRate) or 0
	local batch = (rollsCount > 0 and _roll and _roll.RollOfflineBatch) and _roll.RollOfflineBatch(player, rollsCount) or { rolls = 0, items = {} }
	-- pending (NIEWYDANE do CLAIM). coinsRaw pre-coinMult (Award przy CLAIM naklada mult).
	_pending[player] = { coinsRaw = raw, items = batch.items, rolls = batch.rolls }
	-- podglad: monety po coinMult (do wyswietlenia) + top-N dropow
	local coinMult = (st and st.coinMult) or 1
	local displayCoins = math.floor(raw * coinMult + 0.5)
	local drops = {}
	for i = 1, math.min(#batch.items, ocfg.dropsShown or 5) do
		local it = batch.items[i]
		drops[#drops + 1] = { unitId = it.unitId, qty = it.qty, oddsN = it.rarityN }
	end
	return { coins = displayCoins, rolls = batch.rolls, seconds = seconds, drops = drops, doubleId = ocfg.doubleProductId or 0 }
end

-- CLAIM: przyznaj oczekujace nagrody offline x mult (1 = CLAIM, 2 = CLAIM X2). Idempotentne (pending czyszczone).
function EconomyService.ClaimOffline(player, mult)
	local p = _pending[player]
	if not p then return { ok = false } end
	_pending[player] = nil
	mult = math.max(1, math.floor(mult or 1))
	local coins = (p.coinsRaw > 0) and EconomyService.Award(player, p.coinsRaw * mult, "offline") or 0
	local items = (_roll and _roll.GrantOfflineItems) and _roll.GrantOfflineItems(player, p.items, mult) or 0
	return { ok = true, coins = coins, items = items, mult = mult }
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
	_roll = ServiceRegistry.get("RollService")
	-- po zaladowaniu profilu: salda + offline earn (popup gdy coins>0 lub rolls>0)
	_profile.ProfileLoaded:Connect(function(player)
		pushBalance(player, EconomyService.GetCoins(player))
		EconomyService.SyncRolls(player)
		local result = EconomyService.ComputeOfflineEarnings(player)
		if result.coins > 0 or result.rolls > 0 then
			EconomyService.OfflineEarningsReady:Fire(player, result)
			if _offlineRemote then
				_offlineRemote:FireClient(player, result)
			end
		end
	end)

	-- CLAIM x1 (przycisk Collect)
	Net.get("ClaimOffline").OnServerInvoke = function(player)
		return EconomyService.ClaimOffline(player, 1)
	end
	-- CLAIM X2 = DevProduct 49R -> receipt przyznaje x2. Rejestr tylko gdy ID ustawione (placeholder 0 = off).
	local doubleId = GameConfig.Economy.offline.doubleProductId or 0
	if doubleId > 0 then
		local purchase = ServiceRegistry.get("PurchaseService")
		if purchase and purchase.RegisterProduct then
			purchase.RegisterProduct(doubleId, function(player)
				EconomyService.ClaimOffline(player, 2)
			end)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		_pending[player] = nil
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
