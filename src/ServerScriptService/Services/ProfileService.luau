--!nonstrict
-- ServerScriptService/Services/ProfileService.luau
-- Odpowiedzialnosc: ProfileStore (session-locking), load/release, dostep do danych profilu.
-- NIKT inny nie dotyka ProfileStore. profile==nil -> Kick (nigdy gra bez danych).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ProfileStore = require(
	ServerScriptService:WaitForChild("Server"):WaitForChild("Vendor"):WaitForChild("ProfileStore")
)

local STORE_NAME = "PlayerProfile_v1"

-- §5 architektury — DOKLADNIE te pola.
local PROFILE_TEMPLATE = {
	coins = 0,
	spendableRolls = 0, -- WALUTA (skill tree)
	lifetimeRolls = 0, -- staty/odblokowania; NIGDY nie maleje
	pity = { sinceRare = 0 }, -- licznik rolek od ostatniego dropu N>=guaranteeMinN
	inventory = {}, -- { [invKey]: count }, invKey = unitId.."#"..(mutationId or "")
	placements = {}, -- { [placementId]: {itemId, x, z, mut} } — BEZ rot (auto-face)
	skills = {}, -- { [nodeId]: rank }
	index = {}, -- { [unitId.."#"..variant]: true } (ETAP 2: per-wariant; migracja starych unitId-only)
	waveNumber = 1,
	offlineTs = 0, -- os.time() zapisywany w ProfileReleasing
	purchaseLog = {}, -- idempotencja ProcessReceipt
	serverLuckBuys = 0, -- licznik do rosnacej ceny server luck
}

local ProfileService = {}

local _store = nil
local _profiles: { [Player]: any } = {} -- player -> ProfileStore profile object (Data w .Data)

function ProfileService.Init()
	ProfileService.ProfileLoaded = Signal.new() -- (player, Profile) po udanym StartSessionAsync
	ProfileService.ProfileReleasing = Signal.new() -- (player, Profile) przed release
	_store = ProfileStore.New(STORE_NAME, PROFILE_TEMPLATE)
end

local function onPlayerAdded(player: Player)
	local profile = _store:StartSessionAsync(tostring(player.UserId), {
		-- ForceLoad-owe zachowanie StartSessionAsync + anulowanie gdy gracz wyszedl
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		player:Kick("[war-rng] Nie udalo sie zaladowac profilu. Sprobuj ponownie.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		_profiles[player] = nil
		player:Kick("[war-rng] Profil zwolniony (sesja przejeta przez inny serwer lub zamknieta).")
	end)

	if player.Parent == Players then
		_profiles[player] = profile
		ProfileService.ProfileLoaded:Fire(player, profile.Data)
	else
		profile:EndSession()
	end
end

local function onPlayerRemoving(player: Player)
	local profile = _profiles[player]
	if profile == nil then
		return
	end
	-- ostatni moment na zapis (np. offlineTs, snapshot innych serwisow)
	ProfileService.ProfileReleasing:Fire(player, profile.Data)
	profile.Data.offlineTs = os.time()
	_profiles[player] = nil
	profile:EndSession()
end

function ProfileService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- gracze obecni zanim serwis wystartowal (load async -> ProfileLoaded odpali po startAll)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

-- Dane profilu (mutowalne) lub nil jesli jeszcze nie zaladowany.
function ProfileService.GetProfile(player: Player)
	local profile = _profiles[player]
	return profile ~= nil and profile.Data or nil
end

function ProfileService.IsLoaded(player: Player): boolean
	return _profiles[player] ~= nil
end

-- Hook TYLKO do testow akceptacyjnych (odczyt ksztaltu template bez ladowania DataStore).
function ProfileService._TemplateForTest()
	return PROFILE_TEMPLATE
end

return ProfileService
