--!nonstrict
-- ServerScriptService/Services/PlotService.luau  (§3.3)
-- Odpowiedzialnosc: przydzial gracz<->plot (join/leave), geometria plotu, kierunek auto-face.
-- Kontrakt mapy = tagi CollectionService (ZERO sciezek na sztywno):
--   WR_Plot        (attr PlotId 1..6)              — root plotu (Model)
--   WR_CoreAnchor  (attr PlotId)                   — rdzen plotu
--   WR_PathNode    (attr PlotId, Order)            — waypointy sciezki fali (Order rosnaco)
--   WR_EnemyBase                                   — WIZUAL (nie liczy orientacji)
-- WR_BuildGrid celowo NIE istnieje: origin/wymiary siatki wyprowadzamy z fizycznych kafli `Tile`,
-- i asertujemy Tile.Size == GridConfig.cellSize (warn przy rozjezdzie).
-- faceDirection (poprawka §3.3): normalize(pathNode[Order=1] - gridCenter) — zrodlem jest SCIEZKA
-- (ten sam kontrakt WR_PathNode, ktorym Combat porusza wrogow), nie WR_EnemyBase.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local TILE_NAME = "Tile"

local PlotService = {}

-- plotId -> PlotInfo {plotId, gridOrigin, gridSize, coreCFrame, pathNodes, faceDirection}
local _plots: { [number]: any } = {}
local _built = false

-- przydzial
local _plotByPlayer: { [any]: number } = {} -- key(player) -> plotId
local _playerByPlot: { [number]: any } = {} -- plotId -> key(player)

-- ── budowa geometrii z tagow ──────────────────────────────────────────────
local function collectByPlotId(tag: string)
	local byId: { [number]: { any } } = {}
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		local pid = inst:GetAttribute("PlotId")
		if pid ~= nil then
			byId[pid] = byId[pid] or {}
			table.insert(byId[pid], inst)
		end
	end
	return byId
end

-- origin/wymiary/center z kafli Tile danego plotu
local function deriveGrid(plotModel: Instance, plotId: number)
	local cellSize = GameConfig.Grid.cellSize
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local topY, tileSpan, n = 0, nil, 0
	for _, d in ipairs(plotModel:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == TILE_NAME then
			n += 1
			tileSpan = d.Size.X
			topY = d.Position.Y + d.Size.Y * 0.5
			local p = d.Position
			minX = math.min(minX, p.X)
			maxX = math.max(maxX, p.X)
			minZ = math.min(minZ, p.Z)
			maxZ = math.max(maxZ, p.Z)
		end
	end

	if n == 0 then
		warn(("[PlotService] Plot %d: brak kafli '%s' — nie wyprowadze siatki."):format(plotId, TILE_NAME))
		return nil
	end
	-- asercja kontraktu: fizyczny kafel == cellSize configu
	if tileSpan and math.abs(tileSpan - cellSize) > 1e-3 then
		warn(("[PlotService] Plot %d: Tile.Size=%.3f != GridConfig.cellSize=%.3f (rozjazd siatki!)")
			:format(plotId, tileSpan, cellSize))
	end
	local width, depth = GameConfig.Grid.width, GameConfig.Grid.depth
	local spanX = math.floor((maxX - minX) / cellSize + 0.5) + 1
	local spanZ = math.floor((maxZ - minZ) / cellSize + 0.5) + 1
	if spanX ~= width or spanZ ~= depth then
		warn(("[PlotService] Plot %d: span kafli %dx%d != config %dx%d")
			:format(plotId, spanX, spanZ, width, depth))
	end

	-- KONWENCJA: gridOrigin = rog min (granica komorki), swiatowo osiowany.
	-- srodek komorki 1-indeks (x,z) = gridOrigin.Position + (cellSize*(x-0.5), 0, cellSize*(z-0.5)).
	local gridOrigin = CFrame.new(minX - cellSize * 0.5, topY, minZ - cellSize * 0.5)
	local center = Vector3.new((minX + maxX) * 0.5, topY, (minZ + maxZ) * 0.5)
	return gridOrigin, Vector2int16.new(width, depth), center
end

local function buildPlot(plotModel: Instance, plotId: number, coresById, nodesById)
	local gridOrigin, gridSize, center = deriveGrid(plotModel, plotId)
	if not gridOrigin then
		return nil
	end

	-- rdzen
	local coreCFrame = nil
	local cores = coresById[plotId]
	if cores and cores[1] then
		coreCFrame = cores[1]:IsA("BasePart") and cores[1].CFrame or cores[1]:GetPivot()
	else
		warn(("[PlotService] Plot %d: brak WR_CoreAnchor."):format(plotId))
	end

	-- sciezka: sort po Order rosnaco -> {CFrame}
	local pathNodes = {}
	local raw = nodesById[plotId] or {}
	table.sort(raw, function(a, b)
		return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0)
	end)
	for _, node in ipairs(raw) do
		pathNodes[#pathNodes + 1] = node:IsA("BasePart") and node.CFrame or node:GetPivot()
	end

	-- faceDirection = normalize(pathNode[Order=1] - gridCenter), plaski (Y=0)
	local faceDirection = Vector3.new(0, 0, 1)
	if pathNodes[1] then
		local d = pathNodes[1].Position - center
		local flat = Vector3.new(d.X, 0, d.Z)
		if flat.Magnitude > 1e-4 then
			faceDirection = flat.Unit
		else
			warn(("[PlotService] Plot %d: pathNode[1] pokrywa sie z centrum — faceDirection domyslny."):format(plotId))
		end
	else
		warn(("[PlotService] Plot %d: brak WR_PathNode — faceDirection domyslny."):format(plotId))
	end

	return {
		plotId = plotId,
		gridOrigin = gridOrigin,
		gridSize = gridSize,
		coreCFrame = coreCFrame,
		pathNodes = pathNodes,
		faceDirection = faceDirection,
	}
end

local function ensureBuilt()
	if _built then
		return
	end
	_built = true
	local coresById = collectByPlotId("WR_CoreAnchor")
	local nodesById = collectByPlotId("WR_PathNode")
	for _, plotModel in ipairs(CollectionService:GetTagged("WR_Plot")) do
		local pid = plotModel:GetAttribute("PlotId")
		if pid == nil then
			warn(("[PlotService] WR_Plot bez atrybutu PlotId: %s"):format(plotModel:GetFullName()))
		else
			local info = buildPlot(plotModel, pid, coresById, nodesById)
			if info then
				_plots[pid] = info
			end
		end
	end
end

-- ── przydzial ──────────────────────────────────────────────────────────────
-- najnizszy wolny plotId; nil gdy brak (maxPlayers powinien byc <= liczby plotow)
local function assignPlot(playerKey: any): number?
	ensureBuilt()
	if _plotByPlayer[playerKey] then
		return _plotByPlayer[playerKey]
	end
	local ids = {}
	for id in pairs(_plots) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		if _playerByPlot[id] == nil then
			_plotByPlayer[playerKey] = id
			_playerByPlot[id] = playerKey
			PlotService.PlotAssigned:Fire(playerKey, _plots[id])
			return id
		end
	end
	warn("[PlotService] Brak wolnego plotu dla gracza — sprawdz MaxPlayers vs liczba plotow.")
	return nil
end

local function releasePlot(playerKey: any)
	local id = _plotByPlayer[playerKey]
	if id == nil then
		return
	end
	_plotByPlayer[playerKey] = nil
	_playerByPlot[id] = nil
	PlotService.PlotReleased:Fire(playerKey, id)
end

-- ── spawn gracza na SWOIM placu (nigdy na globalnym SpawnLocation / osi baz wroga Z=0) ──
-- CFrame spawnu = srodek siatki plotu, tuz nad kaflami, patrzac w strone nadchodzacych wrogow
-- (faceDirection). Stary PlotAssignment robil to sam; PlotService przejmuje.
local function plotSpawnCFrame(plot): CFrame
	local o = plot.gridOrigin
	local cs = GameConfig.Grid.cellSize
	local w, d = plot.gridSize.X, plot.gridSize.Y
	local center = o.Position + Vector3.new(cs * w * 0.5, 0, cs * d * 0.5)
	local spawnPos = Vector3.new(center.X, o.Position.Y + 5, center.Z) -- ~5 studow nad kaflami
	return CFrame.lookAlong(spawnPos, plot.faceDirection)
end

local function positionCharacter(player: Player, char: Model)
	local id = _plotByPlayer[player]
	if id == nil then
		id = assignPlot(player)
	end
	local plot = id and _plots[id]
	if not plot then
		warn(("[PlotService] positionCharacter: brak plotu dla %s"):format(player.Name))
		return
	end
	if not char:FindFirstChild("HumanoidRootPart") then
		char:WaitForChild("HumanoidRootPart", 5)
	end
	if char.PrimaryPart or char:FindFirstChild("HumanoidRootPart") then
		char:PivotTo(plotSpawnCFrame(plot))
	end
end

-- Roblox rzucalby graczy na globalny SpawnLocation (0,0,0 = os baz wroga Z=0). Neutralizujemy.
local function neutralizeGlobalSpawns()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("SpawnLocation") then
			inst.Enabled = false
			inst.Neutral = true
		end
	end
end

local function wirePlayer(player: Player)
	assignPlot(player)
	player.CharacterAdded:Connect(function(char)
		positionCharacter(player, char)
	end)
	if player.Character then
		positionCharacter(player, player.Character)
	end
end

-- ── API (§3.3) ───────────────────────────────────────────────────────────────
function PlotService.GetPlot(player: Player)
	local id = _plotByPlayer[player]
	return id and _plots[id] or nil
end

function PlotService.GetPlayerByPlot(plotId: number)
	local key = _playerByPlot[plotId]
	-- w produkcji key to Player; w testach moze byc dowolny klucz
	return key
end

function PlotService.Init()
	PlotService.PlotAssigned = Signal.new() -- (player, PlotInfo)
	PlotService.PlotReleased = Signal.new() -- (player, plotId)
end

function PlotService.Start()
	ensureBuilt()
	neutralizeGlobalSpawns()
	Players.PlayerAdded:Connect(wirePlayer)
	Players.PlayerRemoving:Connect(releasePlot)
	for _, player in ipairs(Players:GetPlayers()) do
		wirePlayer(player)
	end
end

-- ── Hooki TYLKO do testow akceptacyjnych ─────────────────────────────────────
function PlotService._BuildAllForTest()
	ensureBuilt()
	return _plots
end
function PlotService._SpawnCFrameForTest(plotId: number): CFrame?
	ensureBuilt()
	local plot = _plots[plotId]
	return plot and plotSpawnCFrame(plot) or nil
end
function PlotService._AssignForTest(key: any): number?
	return assignPlot(key)
end
function PlotService._ReleaseForTest(key: any)
	releasePlot(key)
end
function PlotService._GetPlotIdForTest(key: any): number?
	return _plotByPlayer[key]
end

return PlotService
