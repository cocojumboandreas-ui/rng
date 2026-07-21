--!nonstrict
-- WR_SkillTestHarness  (TYMCZASOWY — test UI drzewka; USUŃ po weryfikacji)
-- Przyznaje walutę testową (coins + spendableRolls) na żądanie klienta (WR_GrantTest),
-- żeby na urządzeniu dało się kupować węzły w drzewku bez grindu. INERTNY do kliknięcia.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local reg = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("ServiceRegistry"))

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local grant = ensureRemote("WR_GrantTest")

grant.OnServerEvent:Connect(function(player)
	local Economy = reg.get("EconomyService")
	local Profile = reg.get("ProfileService")
	local data = Profile.GetProfile(player)
	if not data then
		return
	end
	Economy.Award(player, 5000, "skilltest") -- coins (+ CoinsSync)
	data.spendableRolls += 500 -- rolki testowe
	Economy.SyncRolls(player) -- RollsSync
	print(("[WR_SkillTest] grant +5000 coins +500 rolls -> %s"):format(player.Name))
end)
