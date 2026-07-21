--!nonstrict
-- WR_IndexTestHarness  (TYMCZASOWY — test UI kolekcji; USUŃ po weryfikacji)
-- Odkrywa kolejne typy jednostek na żądanie klienta (WR_DiscoverTest), żeby na urządzeniu
-- widać było jak indeks się zapełnia + rośnie bonus luck. Używa PRAWDZIWEGO Index.Discover
-- (więc idzie pełna ścieżka: profile.index -> IndexUpdated -> StatProfile.Recompute -> klient).
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
local discover = ensureRemote("WR_DiscoverTest")

-- odkryj do N kolejnych jeszcze-nieodkrytych typow (howMany, domyslnie 3)
discover.OnServerEvent:Connect(function(player, howMany)
	local Index = reg.get("IndexService")
	local Profile = reg.get("ProfileService")
	local data = Profile.GetProfile(player)
	if not data then
		return
	end
	local n = tonumber(howMany) or 3
	local done = 0
	for id in pairs(GameConfig.Units) do
		if done >= n then
			break
		end
		if not data.index[id] then
			if Index.Discover(player, id) then
				done += 1
			end
		end
	end
	print(("[WR_IndexTest] odkryto %d typow -> %s"):format(done, player.Name))
end)
