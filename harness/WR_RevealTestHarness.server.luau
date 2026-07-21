--!nonstrict
-- WR_RevealTestHarness  (TYMCZASOWY — test reveal + mutacje; USUŃ po weryfikacji)
-- Na żądanie klienta (WR_ForceReveal, arg=kind): wypchnij RollResult.
--   kind="real" -> prawdziwa rolka (RollRequest -> prawdziwy RollResult).
--   kind="x2"/"x4"/"x8" -> fabrykowany RollResult z mutacją + jednostka o różnym tierze rarity,
--     żeby wymusić każdy tier kaskady mnożnika ORAZ intensywność rewealu.
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
local force = ensureRemote("WR_ForceReveal")

local PRESETS = {
	x2 = { unitId = "soldier", rarityN = 8, mutation = { id = "x2", mult = 2 } }, -- tier1 + x2
	x4 = { unitId = "rocket_soldier", rarityN = 60, mutation = { id = "x4", mult = 4 } }, -- tier3 + x4
	x8 = { unitId = "tank", rarityN = 1500, mutation = { id = "x8", mult = 8 } }, -- tier5 + x8
}

force.OnServerEvent:Connect(function(player, kind)
	if kind == "real" then
		reg.get("RollService").RequestRoll(player) -- prawdziwa rolka -> prawdziwy RollResult
		return
	end
	local preset = PRESETS[kind]
	if preset then
		Net.get("RollResult"):FireClient(player, {
			unitId = preset.unitId,
			rarityN = preset.rarityN,
			mutation = preset.mutation,
			pityTriggered = false,
		})
	end
end)
