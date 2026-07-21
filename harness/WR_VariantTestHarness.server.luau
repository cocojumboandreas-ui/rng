--!nonstrict
-- WR_VariantTestHarness  (TYMCZASOWY — test finish wariantu w revealu; USUŃ po weryfikacji)
-- Na żądanie klienta (WR_ForceVariant, arg=kind): wypchnij fabrykowany RollResult z variantem.
--   Wizualny test overlay finishu (shiny/galaxy) w RollRevealController. Nie ksieguje do inventory.
--   galaxy rzadszy -> mocniejszy flourish (strong); testujemy tez galaxy+x8+tier5 (max intensywnosc).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local force = ensureRemote("WR_ForceVariant")

local PRESETS = {
	shiny = { unitId = "soldier", rarityN = 8, mutation = nil, variant = "shiny" }, -- shiny czysty (tier1)
	shiny_x4 = { unitId = "rocket_soldier", rarityN = 60, mutation = { id = "x4", mult = 4 }, variant = "shiny" }, -- shiny + x4 (niezaleznosc osi)
	galaxy = { unitId = "soldier", rarityN = 8, mutation = nil, variant = "galaxy" }, -- galaxy czysty (mocny flourish nawet na tier1)
	galaxy_max = { unitId = "tank", rarityN = 1500, mutation = { id = "x8", mult = 8 }, variant = "galaxy" }, -- galaxy + x8 + tier5 = max
}

force.OnServerEvent:Connect(function(player, kind)
	local preset = PRESETS[kind]
	if preset then
		Net.get("RollResult"):FireClient(player, {
			unitId = preset.unitId,
			rarityN = preset.rarityN,
			mutation = preset.mutation,
			variant = preset.variant,
			pityTriggered = false,
		})
	end
end)
