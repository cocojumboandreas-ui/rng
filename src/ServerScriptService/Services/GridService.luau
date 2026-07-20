--!nonstrict
-- ServerScriptService/Services/GridService.luau  (§3.6 + §7)
-- Occupancy multi-cell + cellBudget. CZYSTA logika zajetosci — NIE stawia modeli, nie zna Workspace.
-- DWA NIEZALEZNE sprawdzenia (nie wolno ich scalac):
--   A) bounds + kolizja footprintu (kazda kratka)
--   B) budzet ZAJETYCH kratek (suma footprintow) vs Stats.cellBudget  (to NIE liczba sztuk)
-- deps: StatProfileService, PlotService (wymiary siatki; tu bierzemy z GridConfig — jednolite 9x12).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local GridMath = require(Framework:WaitForChild("GridMath"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local GridService = {}

local _stat = nil
-- stan per gracz
local _state: { [any]: any } = {} -- player -> {occupancy={key=placementId}, usedCells=n, placements={pid={unitId,x,z}}}

local function stateOf(player)
	local s = _state[player]
	if not s then
		s = { occupancy = {}, usedCells = 0, placements = {} }
		_state[player] = s
	end
	return s
end

local function footprintOf(unitId: string)
	local u = GameConfig.Units[unitId]
	return u and u.footprint or nil
end

local function budgetOf(player): number
	if _stat then
		local stats = _stat.Get(player)
		if stats and stats.cellBudget then
			return stats.cellBudget
		end
	end
	return GameConfig.Grid.baseCellBudget
end

-- (ok, reason?) — reason: "OutOfBounds" | "Occupied" | "BudgetExceeded" | "UnknownUnit"
function GridService.CanPlace(player, unitId: string, cellX: number, cellZ: number)
	local fp = footprintOf(unitId)
	if not fp then
		return false, "UnknownUnit"
	end
	local s = stateOf(player)
	local width, depth = GameConfig.Grid.width, GameConfig.Grid.depth

	-- A) bounds + kolizja
	for _, c in ipairs(GridMath.footprintCells(cellX, cellZ, fp)) do
		if c.x < 1 or c.x > width or c.z < 1 or c.z > depth then
			return false, "OutOfBounds"
		end
		if s.occupancy[GridMath.key(c.x, c.z)] ~= nil then
			return false, "Occupied"
		end
	end

	-- B) budzet kratek (osobno!)
	local cost = fp.w * fp.d
	if s.usedCells + cost > budgetOf(player) then
		return false, "BudgetExceeded"
	end
	return true
end

-- Oznacz WSZYSTKIE kratki footprintu tym samym placementId; usedCells += cost.
function GridService.Occupy(player, placementId: string, unitId: string, cellX: number, cellZ: number)
	local fp = footprintOf(unitId)
	if not fp then
		return
	end
	local s = stateOf(player)
	for _, c in ipairs(GridMath.footprintCells(cellX, cellZ, fp)) do
		s.occupancy[GridMath.key(c.x, c.z)] = placementId
	end
	s.usedCells += fp.w * fp.d
	s.placements[placementId] = { unitId = unitId, x = cellX, z = cellZ }
end

-- Wyczysc wszystkie kratki placementId; usedCells -= cost.
function GridService.Free(player, placementId: string)
	local s = stateOf(player)
	local p = s.placements[placementId]
	if not p then
		return
	end
	local fp = footprintOf(p.unitId)
	if fp then
		for _, c in ipairs(GridMath.footprintCells(p.x, p.z, fp)) do
			if s.occupancy[GridMath.key(c.x, c.z)] == placementId then
				s.occupancy[GridMath.key(c.x, c.z)] = nil
			end
		end
		s.usedCells -= fp.w * fp.d
	end
	s.placements[placementId] = nil
end

function GridService.GetUsedCells(player): number
	return stateOf(player).usedCells
end

function GridService.GetBudget(player): number
	return budgetOf(player)
end

function GridService.GetPlacements(player)
	return stateOf(player).placements
end

function GridService.Init() end

function GridService.Start()
	_stat = ServiceRegistry.get("StatProfileService")
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		_state[player] = nil
	end)
end

-- Hooki TYLKO do testow.
function GridService._SetStatProfileForTest(fake)
	_stat = fake
end
function GridService._ResetForTest(player)
	_state[player] = nil
end

return GridService
