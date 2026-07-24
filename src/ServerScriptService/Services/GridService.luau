--!nonstrict
-- ServerScriptService/Services/GridService.luau  (§3.6 + §7 + STACKING)
-- Zajetosc PIONOWA (stosy) + cellBudget. CZYSTA logika — NIE stawia modeli, nie zna Workspace.
-- STACKING: kazda kratka ma STOS warstw. Jednostke mozna postawic gdy WSZYSTKIE kratki footprintu maja
-- ROWNA wysokosc H; jesli H>0, wierzch KAZDEJ musi byc PLATFORMA (blok, nie bron, nie pulapka).
-- Bloki = platformy (mozna na nich stawiac); bronie i pulapki = NIE. Jednostka siada na warstwie H.
-- Usuwanie tylko z GORY (jednostka musi byc na wierzchu wszystkich swoich kratek) — brak kaskady.
-- Budzet = suma ZAJETYCH kratek (footprint * warstwy), nie liczba sztuk.
-- deps: StatProfileService (cellBudget), PlotService (kratki rdzenia = rezerwacja).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local GridMath = require(Framework:WaitForChild("GridMath"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local GridService = {}

local _stat = nil
local _plot = nil -- PlotService (kratki rdzenia = rezerwacja)
-- stan per gracz: stacks[cellKey] = { {pid,unitId}, ... } (dol->gora); usedCells; placements[pid]={unitId,x,z,layer}
local _state: { [any]: any } = {}

local function stateOf(player)
	local s = _state[player]
	if not s then
		s = { stacks = {}, usedCells = 0, placements = {} }
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

-- PLATFORMA = blok, na ktorym mozna stawiac (nie bron, nie pulapka). Bron ma combat; pulapka = category "trap".
local function isPlatform(unitId: string): boolean
	local u = GameConfig.Units[unitId]
	return u ~= nil and u.combat == nil and u.category ~= "trap"
end

local function reservedCells(player)
	local reserved = {}
	local plot = _plot and _plot.GetPlot(player)
	if plot and plot.coreCells then
		for _, cc in ipairs(plot.coreCells) do
			reserved[GridMath.key(cc.x, cc.z)] = true
		end
	end
	return reserved
end

-- (ok, reason?) — reason: UnknownUnit|OutOfBounds|Core|NoSupport|CantStack|BudgetExceeded
function GridService.CanPlace(player, unitId: string, cellX: number, cellZ: number)
	local fp = footprintOf(unitId)
	if not fp then
		return false, "UnknownUnit"
	end
	local s = stateOf(player)
	local width, depth = GameConfig.Grid.width, GameConfig.Grid.depth
	local reserved = reservedCells(player)
	local cells = GridMath.footprintCells(cellX, cellZ, fp)

	-- A) bounds + rdzen
	for _, c in ipairs(cells) do
		if c.x < 1 or c.x > width or c.z < 1 or c.z > depth then
			return false, "OutOfBounds"
		end
		if reserved[GridMath.key(c.x, c.z)] then
			return false, "Core"
		end
	end

	-- B) STOS: rowna wysokosc na wszystkich kratkach; jesli > 0, wierzch = platforma
	local H = nil
	for _, c in ipairs(cells) do
		local stack = s.stacks[GridMath.key(c.x, c.z)]
		local h = stack and #stack or 0
		if H == nil then
			H = h
		elseif h ~= H then
			return false, "NoSupport" -- nierowny stos pod footprintem (np. brak bloku pod czescia)
		end
	end
	if H and H > 0 then
		for _, c in ipairs(cells) do
			local stack = s.stacks[GridMath.key(c.x, c.z)]
			local top = stack[#stack]
			if not (top and isPlatform(top.unitId)) then
				return false, "CantStack" -- na wierzchu jest bron/pulapka -> nie mozna stawiac
			end
		end
	end

	-- C) budzet kratek (osobno!)
	local cost = fp.w * fp.d
	if s.usedCells + cost > budgetOf(player) then
		return false, "BudgetExceeded"
	end
	return true
end

-- Zajmij footprint na WIERZCHU stosow (po CanPlace wszystkie kratki maja rowna wysokosc H).
-- Zwraca WARSTWE (0-based), na ktorej siedzi jednostka -> renderer liczy Y = ziemia + layer*wysokosc.
function GridService.Occupy(player, placementId: string, unitId: string, cellX: number, cellZ: number)
	local fp = footprintOf(unitId)
	if not fp then
		return 0
	end
	local s = stateOf(player)
	local cells = GridMath.footprintCells(cellX, cellZ, fp)
	local firstStack = s.stacks[GridMath.key(cells[1].x, cells[1].z)]
	local layer = firstStack and #firstStack or 0
	for _, c in ipairs(cells) do
		local k = GridMath.key(c.x, c.z)
		s.stacks[k] = s.stacks[k] or {}
		table.insert(s.stacks[k], { pid = placementId, unitId = unitId })
	end
	s.usedCells += fp.w * fp.d
	s.placements[placementId] = { unitId = unitId, x = cellX, z = cellZ, layer = layer }
	return layer
end

-- Czy mozna usunac? Tylko gdy jednostka jest NA WIERZCHU wszystkich swoich kratek (usuwanie z gory, bez kaskady).
function GridService.CanRemove(player, placementId: string): boolean
	local s = stateOf(player)
	local p = s.placements[placementId]
	if not p then
		return false
	end
	local fp = footprintOf(p.unitId)
	if not fp then
		return false
	end
	for _, c in ipairs(GridMath.footprintCells(p.x, p.z, fp)) do
		local stack = s.stacks[GridMath.key(c.x, c.z)]
		if not stack or (stack[#stack] and stack[#stack].pid ~= placementId) then
			return false -- cos stoi NAD ta jednostka
		end
	end
	return true
end

-- Zwolnij jednostke (usuwa jej warstwe ze wszystkich kratek). Zaklada CanRemove (wierzch).
function GridService.Free(player, placementId: string)
	local s = stateOf(player)
	local p = s.placements[placementId]
	if not p then
		return
	end
	local fp = footprintOf(p.unitId)
	if fp then
		for _, c in ipairs(GridMath.footprintCells(p.x, p.z, fp)) do
			local k = GridMath.key(c.x, c.z)
			local stack = s.stacks[k]
			if stack then
				for i = #stack, 1, -1 do
					if stack[i].pid == placementId then
						table.remove(stack, i)
					end
				end
				if #stack == 0 then
					s.stacks[k] = nil
				end
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

-- warstwa (0-based) danej jednostki — renderer liczy Y = ziemia + layer * wysokosc warstwy
function GridService.GetLayer(player, placementId: string): number
	local p = stateOf(player).placements[placementId]
	return p and p.layer or 0
end

function GridService.Init() end

function GridService.Start()
	_stat = ServiceRegistry.get("StatProfileService")
	_plot = ServiceRegistry.get("PlotService")
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
