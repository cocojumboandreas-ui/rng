--!nonstrict
-- ServerScriptService/Services/IndexService.luau  (§3.13 — CZESC SLICE'a: tylko Discover)
-- SLICE: RollService (§6 krok 4) wola Index.Discover, wiec zapisujemy odkrycie do profile.index.
-- POST-BRAMKA: progi IndexConfig + GetLuckBonus zasilajace StatProfile + UI indeksu.
-- Tu GetLuckBonus zwraca 0 (StatProfile i tak go nie wola w slice).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))

local IndexService = {}

local _profileService = nil

function IndexService.Init()
	IndexService.Discovered = Signal.new() -- (player, unitId) — pierwsze odkrycie
end

function IndexService.Start()
	_profileService = ServiceRegistry.get("ProfileService")
end

-- Zapis odkrycia jednostki (idempotentny). Jedyny writer profile.index.
function IndexService.Discover(player, unitId: string)
	local data = _profileService and _profileService.GetProfile(player)
	if not data then
		return
	end
	if not data.index[unitId] then
		data.index[unitId] = true
		IndexService.Discovered:Fire(player, unitId)
	end
end

-- SLICE: brak bonusu luck z indeksu (POST-BRAMKA).
function IndexService.GetLuckBonus(player): number
	return 0
end

-- Hook TYLKO do testow.
function IndexService._SetProfileServiceForTest(fake)
	_profileService = fake
end

return IndexService
