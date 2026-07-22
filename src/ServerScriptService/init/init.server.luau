--!strict
-- Server bootstrap: rejestruje serwisy -> initAll -> startAll.
-- Kolejnosc rejestracji = kolejnosc Init/Start (sekcja 2 architektury).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Services = ServerScriptService:WaitForChild("Services")

-- Sekcja 2: ProfileService -> StatProfileService -> PlotService -> EconomyService ->
-- InventoryService -> IndexService -> RollService -> GridService -> BuildService ->
-- CoreService -> CombatService -> WaveService -> BaseDoorService -> SkillService -> PurchaseService.
local ORDER = {
	"ProfileService",
	"StatProfileService",
	"PlotService",
	"EconomyService",
	"InventoryService",
	"IndexService",
	"RollService",
	"GridService",
	"BuildService",
	"CoreService",
	"CombatService",
	"WaveService",
	"BaseDoorService",
	"SkillService",
	"PurchaseService",
	"DevService",
}

for _, name in ipairs(ORDER) do
	local module = Services:WaitForChild(name)
	ServiceRegistry.register(name, require(module))
end

ServiceRegistry.initAll()
ServiceRegistry.startAll()
