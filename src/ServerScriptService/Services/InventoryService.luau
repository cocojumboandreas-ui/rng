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

-- invKey = unitId .. "#" .. (mutationId or "") .. "#" .. variant   (variant domyslnie "regular")
local function invKey(unitId: string, mutation, variant): string
	return unitId .. "#" .. (mutation and mutation.id or "") .. "#" .. (variant or "regular")
end

-- MIGRACJA: stare klucze "unitId#mut" (2 czesci, sprzed osi wariantu) -> "unitId#mut#regular".
local function migrateInventory(inventory)
	local rekey = {}
	for k in pairs(inventory) do
		if select(2, k:gsub("#", "#")) < 2 then -- <2 znakow "#" = stary 2-czesciowy klucz
			rekey[#rekey + 1] = k
		end
	end
	for _, oldK in ipairs(rekey) do
		local newK = oldK .. "#regular"
		inventory[newK] = (inventory[newK] or 0) + inventory[oldK]
		inventory[oldK] = nil
	end
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
	-- migracja starych kluczy przy zaladowaniu profilu (brak wariantu -> regular)
	_profileService.ProfileLoaded:Connect(function(player)
		local data = _profileService.GetProfile(player)
		if data and data.inventory then
			migrateInventory(data.inventory)
		end
	end)
end

-- Publiczny budowniczy klucza (BuildService liczy kanoniczny invKey do walidacji wlasnosci).
function InventoryService.KeyFor(unitId: string, mutation, variant): string
	return invKey(unitId, mutation, variant)
end

function InventoryService.Add(player, unitId: string, mutation, variant)
	local i = inv(player)
	if not i then
		return
	end
	local k = invKey(unitId, mutation, variant)
	i[k] = (i[k] or 0) + 1
	InventoryService.Changed:Fire(player)
end

-- false jesli brak sztuki; wolane przy stawianiu (Build)
function InventoryService.Consume(player, unitId: string, mutation, variant): boolean
	local i = inv(player)
	if not i then
		return false
	end
	local k = invKey(unitId, mutation, variant)
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
function InventoryService.Refund(player, unitId: string, mutation, variant)
	InventoryService.Add(player, unitId, mutation, variant)
end

function InventoryService.GetCounts(player)
	local i = inv(player)
	return i and table.clone(i) or {}
end

-- Hooki TYLKO do testow.
function InventoryService._KeyForTest(unitId, mutation, variant)
	return invKey(unitId, mutation, variant)
end
function InventoryService._MigrateForTest(inventory)
	migrateInventory(inventory)
end
function InventoryService._SetProfileServiceForTest(fake)
	_profileService = fake
end

return InventoryService
