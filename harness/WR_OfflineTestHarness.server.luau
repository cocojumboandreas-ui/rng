--!nonstrict
-- WR_OfflineTestHarness  (TYMCZASOWY — test popup offline; USUŃ po weryfikacji)
-- Na żądanie klienta (WR_SimOfflineTest, arg=hours): ustaw offlineTs = now - hours*3600,
-- policz offline earn (PRAWDZIWY grant + guardy) i wypchnij OfflineEarnings (popup).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local reg = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("ServiceRegistry"))
local Net = require(ReplicatedStorage.Framework.Net)

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local sim = ensureRemote("WR_SimOfflineTest")

sim.OnServerEvent:Connect(function(player, hours)
	local Eco = reg.get("EconomyService")
	local data = reg.get("ProfileService").GetProfile(player)
	if not data then
		return
	end
	local h = tonumber(hours) or 2
	data.offlineTs = os.time() - math.floor(h * 3600)
	local result = Eco.ComputeOfflineEarnings(player) -- realny grant + coinMult + reset offlineTs
	Net.get("OfflineEarnings"):FireClient(player, result)
	print(("[WR_OfflineTest] sim %sh -> %d monet (%ds)"):format(tostring(h), result.coins, result.seconds))
end)
