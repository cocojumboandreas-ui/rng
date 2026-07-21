--!nonstrict
-- WR_MutTestHarness  (TYMCZASOWY — test kaskady mutacji; USUŃ po weryfikacji)
-- Na zadanie klienta (WR_ForceMut, arg=mult) wypycha fabrykowany RollResult z mutacja o danym mnozniku
-- -> reveal odpala kaskade koniczyn (2x -> ... -> mult). NIE ksieguje do inventory (czysto wizualne).
local RS = game:GetService("ReplicatedStorage")
local Net = require(RS:WaitForChild("Framework"):WaitForChild("Net"))
local GameConfig = require(RS.Content.Config.GameConfig)

local force = RS:FindFirstChild("WR_ForceMut")
if not force then
	force = Instance.new("RemoteEvent")
	force.Name = "WR_ForceMut"
	force.Parent = RS
end

force.OnServerEvent:Connect(function(player, mult)
	mult = tonumber(mult) or 128
	local unitId = "tank_soldier" -- ladny model do pokazu
	local u = GameConfig.Units[unitId]
	Net.get("RollResult"):FireClient(player, {
		unitId = unitId,
		rarityN = u and u.rarityN or 100,
		mutation = { id = "x" .. mult, mult = mult },
		variant = "regular",
		pityTriggered = false,
	})
end)
