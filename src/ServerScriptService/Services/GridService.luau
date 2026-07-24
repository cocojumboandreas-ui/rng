--!nonstrict
-- ServerScriptService/Services/GridService.luau  (§3.6 + §7 + STACKING warstwy ABSOLUTNE)
-- Zajetosc PIONOWA: kazda kratka ma STOS warstw indeksowanych ABSOLUTNIE (mapa [layer]=wpis, moga byc DZIURY).
-- STAWIANIE: jednostke mozna postawic gdy WSZYSTKIE kratki footprintu maja ROWNA wysokosc H (=max warstwa+1);
--   jesli H>0, wierzch (najwyzsza warstwa) KAZDEJ kratki musi byc PLATFORMA (blok, nie bron/pulapka). Siada na H.
-- EDYCJA/USUWANIE: DOWOLNA jednostka (nie tylko z gory). Usuniecie dolnej NIE przesuwa gornych — zostaja
--   "w powietrzu" (dziura w stosie). Brak kaskady. Wrogowie chodza po pathT, wiec latajace bloki ich nie ruszaja.
-- Budzet = suma ZAJETYCH kratek (footprint * warstwy). deps: StatProfileService (cellBudget), PlotService (rdzen).
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
-- stan per gracz: stacks[cellKey] = { [layer] = {pid,unitId} } (mapa absolutna, dziury OK); usedCells; placements
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

-- wysokosc kratki = najwyzsza zajeta warstwa + 1 (0 gdy pusto). Dziury nie zmieniaja wysokosci.
local function cellHeight(s, k): number
	local stack = s.stacks[k]
	if not stack then
		return 0
	end
	local maxL = -1
	for layer in pairs(stack) do
		if layer > maxL then maxL = layer end
	end
	return maxL + 1
end

-- NAJNIZSZA warstwa L, na ktora zmiesci sie caly footprint (wypelnia DZIURY od dolu, potem wierzch):
-- wszystkie kratki WOLNE na L, i (L==0 albo pod kazda kratka na L-1 stoi PLATFORMA). nil = brak miejsca/podparcia.
local function placementLayer(s, cells)
	local maxH = 0
	for _, c in ipairs(cells) do
		local h = cellHeight(s, GridMath.key(c.x, c.z))
		if h > maxH then maxH = h end
	end
	for L = 0, maxH do
		local ok = true
		for _, c in ipairs(cells) do
			local stack = s.stacks[GridMath.key(c.x, c.z)]
			if stack and stack[L] ~= nil then
				ok = false
				break
			end
			if L > 0 then
				local below = stack and stack[L - 1]
				if not (below and isPlatform(below.unitId)) then
					ok = false
					break
				end
			end
		end
		if ok then
			return L
		end
	end
	return nil
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

	-- B) STOS: musi istniec warstwa gdzie footprint sie zmiesci (wypelnia dziury od dolu, z podparciem platforma)
	if placementLayer(s, cells) == nil then
		return false, "NoSupport"
	end

	-- C) budzet kratek
	local cost = fp.w * fp.d
	if s.usedCells + cost > budgetOf(player) then
		return false, "BudgetExceeded"
	end
	return true
end

-- Zajmij footprint. forcedLayer (opcjonalnie, do restore) = konkretna warstwa; inaczej WIERZCH (rowna wysokosc H).
-- Zwraca warstwe (0-based) -> renderer liczy Y = ziemia + layer*wysokosc.
function GridService.Occupy(player, placementId: string, unitId: string, cellX: number, cellZ: number, forcedLayer: number?)
	local fp = footprintOf(unitId)
	if not fp then
		return 0
	end
	local s = stateOf(player)
	local cells = GridMath.footprintCells(cellX, cellZ, fp)
	local layer = forcedLayer
	if layer == nil then
		layer = placementLayer(s, cells) or 0 -- najnizsza wolna warstwa (wypelnia dziury)
	end
	for _, c in ipairs(cells) do
		local k = GridMath.key(c.x, c.z)
		s.stacks[k] = s.stacks[k] or {}
		s.stacks[k][layer] = { pid = placementId, unitId = unitId }
	end
	s.usedCells += fp.w * fp.d
	s.placements[placementId] = { unitId = unitId, x = cellX, z = cellZ, layer = layer }
	return layer
end

-- Zwolnij jednostke (usuwa jej warstwe ze wszystkich kratek). DOWOLNA warstwa — gorne zostaja "w powietrzu".
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
				stack[p.layer] = nil
				if next(stack) == nil then
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
