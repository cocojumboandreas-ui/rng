--!nonstrict
-- WR_IndexVariantTestHarness  (TYMCZASOWY — test UI kolekcji 4 kategorie; USUŃ po weryfikacji)
-- Odkrywa unit-warianty na żądanie (WR_DiscoverVariant, arg={variant, howMany}). Używa PRAWDZIWEGO
-- Index.Discover(player, unitId, variant) — pełna ścieżka: profile.index -> IndexUpdated ->
-- StatProfile.Recompute -> klient. Pozwala zobaczyć zakładki (regular/shiny/galaxy) + rosnący luck.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local reg = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("ServiceRegistry"))
local GameConfig = require(ReplicatedStorage.Content.Config.GameConfig)

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local discover = ensureRemote("WR_DiscoverVariant")

-- stabilna lista typow (po rarityN rosnaco) — zeby odkrywac po kolei
local function unitOrder()
	local ids = {}
	for id in pairs(GameConfig.Units) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b)
		return GameConfig.Units[a].rarityN < GameConfig.Units[b].rarityN
	end)
	return ids
end

discover.OnServerEvent:Connect(function(player, payload)
	local Index = reg.get("IndexService")
	local Profile = reg.get("ProfileService")
	local data = Profile.GetProfile(player)
	if not data then
		return
	end
	payload = payload or {}
	local variant = payload.variant or "regular"
	local howMany = tonumber(payload.howMany) or 3 -- -1 = wszystko
	local done = 0
	for _, id in ipairs(unitOrder()) do
		if howMany >= 0 and done >= howMany then
			break
		end
		if Index.Discover(player, id, variant) then
			done += 1
		end
	end
	print(("[WR_IndexVariantTest] odkryto %d x %s -> %s"):format(done, variant, player.Name))
end)
