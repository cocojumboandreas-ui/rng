--!nonstrict
-- ServerScriptService/Services/BuildService.luau  (§3.7)
-- Orkiestracja stawiania/usuwania: spina Inventory + Grid + Workspace + faze. Jedyny wlasciciel modeli na plocie.
-- KONTRAKT (decyzja Olo): Net.PlaceUnit(itemId, cellX, cellZ) gdzie itemId = invKey "unitId#mutationId"
--   (dokladnie to co zwraca Inventory.GetCounts). Split na PIERWSZYM "#"; pusty mutationId -> mut=nil.
--   Placement zapisuje {itemId=unitId, x, z, mut=mutationId|nil}.
-- WALIDACJA SERWEROWA (nie ufamy klientowi): faza Building -> legalny unitId (UnitsConfig)
--   -> gracz posiada >=1 DOKLADNEGO wariantu -> Grid.CanPlace -> Occupy -> Inventory.Consume.
-- Zero rotation w danych: orientacja liczona przy stawianiu z PlotInfo.faceDirection.
-- deps: InventoryService, GridService, PlotService, WaveService (faza), ProfileService.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local GridMath = require(Framework:WaitForChild("GridMath"))
local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local BuildService = {}

local _inv, _grid, _plot, _wave, _profile = nil, nil, nil, nil, nil
local _models: { [any]: { [string]: Instance } } = {} -- player -> {placementId -> Model}
local _unitsFolder: Folder? = nil

-- ── helpers czyste ───────────────────────────────────────────────────────────
-- split invKey na PIERWSZYM "#": "soldier#x2" -> "soldier","x2"; "noob#" -> "noob",nil
local function parseItemId(itemId: string)
	local hash = string.find(itemId, "#", 1, true)
	if not hash then
		return itemId, nil
	end
	local unitId = string.sub(itemId, 1, hash - 1)
	local mutId = string.sub(itemId, hash + 1)
	if mutId == "" then
		mutId = nil
	end
	return unitId, mutId
end

local function mutObject(mutId: string?)
	if not mutId then
		return nil
	end
	for _, m in ipairs(GameConfig.Mutation.ladder) do
		if m.id == mutId then
			return { id = m.id, mult = m.mult }
		end
	end
	return { id = mutId } -- nieznana mutacja: ownership-check i tak odrzuci
end

-- ── stan (orkiestracja, bez Workspace) ───────────────────────────────────────
-- (ok, placementId | reason). reason: NotBuilding|UnknownUnit|NotOwned|OutOfBounds|Occupied|BudgetExceeded
local function doPlace(player, itemId: string, cellX: number, cellZ: number)
	if _wave.GetPhase(player) ~= Enums.RunPhase.Building then
		return false, "NotBuilding"
	end
	local unitId, mutId = parseItemId(itemId)
	if GameConfig.Units[unitId] == nil then
		return false, "UnknownUnit"
	end
	-- ownership: gracz musi miec >=1 DOKLADNEGO wariantu (itemId == invKey)
	local counts = _inv.GetCounts(player)
	if (counts[itemId] or 0) < 1 then
		return false, "NotOwned"
	end
	local canOK, reason = _grid.CanPlace(player, unitId, cellX, cellZ)
	if not canOK then
		return false, reason
	end
	local mutation = mutObject(mutId)
	local pid = HttpService:GenerateGUID(false)
	_grid.Occupy(player, pid, unitId, cellX, cellZ)
	if not _inv.Consume(player, unitId, mutation) then
		_grid.Free(player, pid) -- rollback (nie powinno sie zdarzyc po ownership-check)
		return false, "NotOwned"
	end
	local data = _profile.GetProfile(player)
	if data then
		data.placements[pid] = { itemId = unitId, x = cellX, z = cellZ, mut = mutId }
	end
	return true, pid
end

-- (ok, reason). reason: NotBuilding|NoSuchPlacement
local function doRemove(player, placementId: string)
	if _wave.GetPhase(player) ~= Enums.RunPhase.Building then
		return false, "NotBuilding"
	end
	local data = _profile.GetProfile(player)
	local p = data and data.placements[placementId]
	if not p then
		return false, "NoSuchPlacement"
	end
	_grid.Free(player, placementId)
	_inv.Refund(player, p.itemId, mutObject(p.mut))
	data.placements[placementId] = nil
	return true
end

-- ── Workspace (runtime) ──────────────────────────────────────────────────────
local function ensureUnitsFolder(): Folder
	if _unitsFolder and _unitsFolder.Parent then
		return _unitsFolder
	end
	local f = Workspace:FindFirstChild("WR_Units")
	if not f then
		f = Instance.new("Folder")
		f.Name = "WR_Units"
		f.Parent = Workspace
	end
	_unitsFolder = f
	return f
end

local function spawnModel(player, unitId: string, placementId: string, cellX: number, cellZ: number)
	local plot = _plot.GetPlot(player)
	if not plot then
		warn("[BuildService] spawnModel: brak plotu gracza")
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local unitsAssets = assets and assets:FindFirstChild("Units")
	local modelName = GameConfig.Units[unitId].model
	local template = unitsAssets and unitsAssets:FindFirstChild(modelName)
	if not template then
		warn(("[BuildService] brak modelu '%s' w Assets.Units"):format(tostring(modelName)))
		return nil
	end
	local fp = GameConfig.Units[unitId].footprint
	local model = template:Clone()
	local center = GridMath.cellToWorld(plot.gridOrigin, GameConfig.Grid.cellSize, cellX, cellZ, fp).Position
	-- podstawa modelu na kaflach: przesun w gore o pol wysokosci
	local h = model:GetExtentsSize().Y
	local pos = Vector3.new(center.X, plot.gridOrigin.Position.Y + h * 0.5, center.Z)
	model:PivotTo(CFrame.lookAlong(pos, plot.faceDirection))
	model:SetAttribute("PlacementId", placementId)
	model:SetAttribute("OwnerUserId", typeof(player) == "Instance" and player.UserId or 0)
	model.Parent = ensureUnitsFolder()
	_models[player] = _models[player] or {}
	_models[player][placementId] = model
	return model
end

local function despawnModel(player, placementId: string)
	local byPid = _models[player]
	local model = byPid and byPid[placementId]
	if model then
		model:Destroy()
		byPid[placementId] = nil
	end
end

-- ── API (§3.7) ────────────────────────────────────────────────────────────────
-- Odtworzenie plotu po ProfileLoaded: Grid.Occupy + spawn z profile.placements (BEZ Consume).
function BuildService.RestorePlot(player)
	local data = _profile.GetProfile(player)
	if not data or not data.placements then
		return
	end
	for pid, p in pairs(data.placements) do
		_grid.Occupy(player, pid, p.itemId, p.x, p.z)
		spawnModel(player, p.itemId, pid, p.x, p.z)
	end
	BuildService.PlacementChanged:Fire(player)
end

function BuildService.Init()
	BuildService.PlacementChanged = Signal.new() -- (player)
end

function BuildService.Start()
	_inv = ServiceRegistry.get("InventoryService")
	_grid = ServiceRegistry.get("GridService")
	_plot = ServiceRegistry.get("PlotService")
	_wave = ServiceRegistry.get("WaveService")
	_profile = ServiceRegistry.get("ProfileService")

	-- Net.PlaceUnit (RemoteFunction): zwraca {ok, placementId?|reason?}
	Net.get("PlaceUnit").OnServerInvoke = function(player, itemId, cellX, cellZ)
		if type(itemId) ~= "string" or type(cellX) ~= "number" or type(cellZ) ~= "number" then
			return { ok = false, reason = "BadArgs" }
		end
		local ok, res = doPlace(player, itemId, cellX, cellZ)
		if ok then
			spawnModel(player, (select(1, parseItemId(itemId))), res, cellX, cellZ)
			BuildService.PlacementChanged:Fire(player)
			return { ok = true, placementId = res }
		end
		return { ok = false, reason = res }
	end

	-- Net.RemoveUnit (RemoteFunction): zwraca {ok, reason?}
	Net.get("RemoveUnit").OnServerInvoke = function(player, placementId)
		if type(placementId) ~= "string" then
			return { ok = false, reason = "BadArgs" }
		end
		local ok, reason = doRemove(player, placementId)
		if ok then
			despawnModel(player, placementId)
			BuildService.PlacementChanged:Fire(player)
			return { ok = true }
		end
		return { ok = false, reason = reason }
	end

	-- restore po zaladowaniu profilu
	_profile.ProfileLoaded:Connect(function(player)
		BuildService.RestorePlot(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local byPid = _models[player]
		if byPid then
			for _, model in pairs(byPid) do
				model:Destroy()
			end
		end
		_models[player] = nil
	end)
end

-- ── Hooki TYLKO do testow (orkiestracja stanu, bez Workspace) ─────────────────
function BuildService._InjectForTest(deps)
	_inv, _grid, _plot, _wave, _profile = deps.inv, deps.grid, deps.plot, deps.wave, deps.profile
end
function BuildService._DoPlaceForTest(player, itemId, cellX, cellZ)
	return doPlace(player, itemId, cellX, cellZ)
end
function BuildService._DoRemoveForTest(player, placementId)
	return doRemove(player, placementId)
end
function BuildService._ParseItemIdForTest(itemId)
	return parseItemId(itemId)
end

return BuildService
