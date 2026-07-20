--!nonstrict
-- ServerScriptService/Services/InventoryService.luau  (§3.5)
-- Pula wyrollowanych jednostek (do postawienia). Mutacja = wlasnosc EGZEMPLARZA, nie typu,
-- wiec stack per (unitId, mutationId). invKey = unitId .. "#" .. (mutationId or "").
-- Jedyny writer profile.inventory. deps: ProfileService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))

local InventoryService = {}

local _profileService = nil

local function invKey(unitId: string, mutation)
	return unitId .. "#" .. (mutation and mutation.id or "")
end

local function inv(player)
	local data = _profileService and _profileService.GetProfile(player)
	return data and data.inventory or nil
end

function InventoryService.Init()
	InventoryService.Changed = Signal.new() -- (player)
end

function InventoryService.Start()
	_profileService = ServiceRegistry.get("ProfileService")
end

function InventoryService.Add(player, unitId: string, mutation)
	local i = inv(player)
	if not i then
		return
	end
	local k = invKey(unitId, mutation)
	i[k] = (i[k] or 0) + 1
	InventoryService.Changed:Fire(player)
end

-- false jesli brak sztuki; wolane przy stawianiu (Build)
function InventoryService.Consume(player, unitId: string, mutation): boolean
	local i = inv(player)
	if not i then
		return false
	end
	local k = invKey(unitId, mutation)
	if (i[k] or 0) <= 0 then
		return false
	end
	i[k] -= 1
	if i[k] <= 0 then
		i[k] = nil
	end
	InventoryService.Changed:Fire(player)
	return true
end

-- przy usunieciu obiektu z siatki — sztuka wraca do puli
function InventoryService.Refund(player, unitId: string, mutation)
	InventoryService.Add(player, unitId, mutation)
end

function InventoryService.GetCounts(player)
	local i = inv(player)
	return i and table.clone(i) or {}
end

-- Hooki TYLKO do testow.
function InventoryService._KeyForTest(unitId, mutation)
	return invKey(unitId, mutation)
end
function InventoryService._SetProfileServiceForTest(fake)
	_profileService = fake
end

return InventoryService
