--!nonstrict
-- ServerScriptService/Services/BaseDoorService.luau
-- Rozsuwane bramy baz wrogow (MilitaryMap): otwieraja sie na start fali, zamykaja na koniec.
-- Baza (tag WR_EnemyBase) ma 2 bramy podwojne: front (+Z, Door1/Door2) i tyl (-Z, Door3/Door4).
-- Kazda brama = 2 lisce, ktore rozsuwaja sie w osi X (lewy -X, prawy +X) o swoja szerokosc.
-- Mapowanie plot->brama: kolumna X wybiera baze (najblizsza), znak Z spawnu (WR_PathNode Order=1)
-- wybiera strone (front/tyl). Serwer tweenuje Position czesci -> replikuje do wszystkich klientow.
-- deps: WaveService (WaveStarted/WaveEnded), PlotService (GetPlot -> plotId).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))

local BaseDoorService = {}

-- ── tuning ────────────────────────────────────────────────────────────────
local SLIDE_FRAC = 0.95 -- ile szerokosci liscia rozsuwamy (1.0 = pelna)
local OPEN_TIME = 0.55 -- s
local CLOSE_TIME = 0.65 -- s
local DOOR_PREFIX = "Door" -- nazwa modeli lisci

local _wave, _plot = nil, nil
local _gates = {} -- lista bram {leaves={{part,closed,open},...}, state, tweens}
local _gateByPlot = {} -- plotId -> gate

-- ── geometria ──────────────────────────────────────────────────────────────
-- world-AABB (center, size) modelu po 8 rogach kazdej czesci (odporne na obrot).
local function worldAABB(model: Instance)
	local minv = Vector3.new(math.huge, math.huge, math.huge)
	local maxv = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local s = d.Size
			for _, sx in ipairs({ -0.5, 0.5 }) do
				for _, sy in ipairs({ -0.5, 0.5 }) do
					for _, sz in ipairs({ -0.5, 0.5 }) do
						local p = (d.CFrame * CFrame.new(s.X * sx, s.Y * sy, s.Z * sz)).Position
						minv = Vector3.new(math.min(minv.X, p.X), math.min(minv.Y, p.Y), math.min(minv.Z, p.Z))
						maxv = Vector3.new(math.max(maxv.X, p.X), math.max(maxv.Y, p.Y), math.max(maxv.Z, p.Z))
					end
				end
			end
		end
	end
	return (minv + maxv) * 0.5, (maxv - minv)
end

local function leafParts(model: Instance)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts[#parts + 1] = d
		end
	end
	return parts
end

-- ── budowa rejestru bram ─────────────────────────────────────────────────
local function buildGates()
	_gates = {}
	for _, base in ipairs(CollectionService:GetTagged("WR_EnemyBase")) do
		if base:IsDescendantOf(workspace) then
			local baseCf = base:GetBoundingBox()
			local baseCenter = baseCf.Position
			-- zbierz lisce Door* i pogrupuj po stronie (front=+Z / back=-Z)
			local sides = { front = {}, back = {} }
			for _, ch in ipairs(base:GetChildren()) do
				if ch:IsA("Model") and ch.Name:sub(1, #DOOR_PREFIX) == DOOR_PREFIX then
					local c = select(1, worldAABB(ch))
					local sideKey = (c.Z >= baseCenter.Z) and "front" or "back"
					table.insert(sides[sideKey], { model = ch, center = c })
				end
			end
			for sideKey, leaves in pairs(sides) do
				if #leaves >= 2 then
					-- srodek bramy = srednia X lisci -> kierunek rozsuwu kazdego liscia
					local sumX = 0
					for _, lf in ipairs(leaves) do
						sumX += lf.center.X
					end
					local gateCenterX = sumX / #leaves
					local gate = {
						base = base,
						side = sideKey,
						baseCenterX = baseCenter.X,
						baseCenterZ = baseCenter.Z,
						leaves = {},
						state = "closed",
						tweens = {},
					}
					for _, lf in ipairs(leaves) do
						local _, sz = worldAABB(lf.model)
						local dir = (lf.center.X < gateCenterX) and -1 or 1
						local slide = Vector3.new(dir * sz.X * SLIDE_FRAC, 0, 0)
						for _, part in ipairs(leafParts(lf.model)) do
							table.insert(gate.leaves, { part = part, closed = part.Position, open = part.Position + slide })
						end
					end
					table.insert(_gates, gate)
				end
			end
		end
	end
end

-- ── mapowanie plot -> brama (po spawnach WR_PathNode Order=1) ─────────────
local function buildPlotMap()
	_gateByPlot = {}
	-- spawn per plot = najmniejszy Order
	local spawn = {} -- plotId -> Vector3
	local bestOrder = {}
	for _, n in ipairs(CollectionService:GetTagged("WR_PathNode")) do
		local pid = n:GetAttribute("PlotId")
		local ord = n:GetAttribute("Order") or 0
		if pid then
			if bestOrder[pid] == nil or ord < bestOrder[pid] then
				bestOrder[pid] = ord
				spawn[pid] = n:IsA("BasePart") and n.Position or n:GetPivot().Position
			end
		end
	end
	for pid, pos in pairs(spawn) do
		-- najblizsza baza po X, strona po znaku Z spawnu wzgledem srodka bazy
		local best, bestDX = nil, math.huge
		for _, gate in ipairs(_gates) do
			local dx = math.abs(gate.baseCenterX - pos.X)
			local wantSide = (pos.Z >= gate.baseCenterZ) and "front" or "back"
			if gate.side == wantSide and dx < bestDX then
				bestDX = dx
				best = gate
			end
		end
		if best then
			_gateByPlot[pid] = best
		end
	end
end

-- ── animacja ─────────────────────────────────────────────────────────────
local function animateGate(gate, opening: boolean)
	if not gate then
		return
	end
	local target = opening and "open" or "closed"
	if gate.state == target then
		return
	end
	gate.state = target
	for _, t in ipairs(gate.tweens) do
		pcall(function()
			t:Cancel()
		end)
	end
	gate.tweens = {}
	local info = TweenInfo.new(opening and OPEN_TIME or CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, lf in ipairs(gate.leaves) do
		if lf.part and lf.part.Parent then
			local tw = TweenService:Create(lf.part, info, { Position = opening and lf.open or lf.closed })
			tw:Play()
			table.insert(gate.tweens, tw)
		end
	end
end

local function openForPlayer(player)
	local plot = _plot and _plot.GetPlot(player)
	local pid = plot and plot.plotId
	if pid and _gateByPlot[pid] then
		animateGate(_gateByPlot[pid], true)
	end
end

local function closeForPlayer(player)
	local plot = _plot and _plot.GetPlot(player)
	local pid = plot and plot.plotId
	if pid and _gateByPlot[pid] then
		animateGate(_gateByPlot[pid], false)
	end
end

function BaseDoorService.Init() end

function BaseDoorService.Start()
	_wave = ServiceRegistry.get("WaveService")
	_plot = ServiceRegistry.get("PlotService")

	buildGates()
	buildPlotMap()

	if #_gates == 0 then
		warn("[BaseDoorService] Nie znaleziono zadnych bram (WR_EnemyBase + Door*).")
	end

	if _wave and _wave.WaveStarted then
		_wave.WaveStarted:Connect(function(player)
			openForPlayer(player)
		end)
	end
	if _wave and _wave.WaveEnded then
		_wave.WaveEnded:Connect(function(player)
			closeForPlayer(player)
		end)
	end
end

-- ── hooki TYLKO do testow (edit / recznie) ───────────────────────────────
function BaseDoorService._Rebuild()
	buildGates()
	buildPlotMap()
	return #_gates, (function()
		local n = 0
		for _ in pairs(_gateByPlot) do
			n += 1
		end
		return n
	end)()
end
function BaseDoorService._SetAll(open: boolean)
	for _, gate in ipairs(_gates) do
		animateGate(gate, open)
	end
end
function BaseDoorService._SetPlot(plotId: number, open: boolean)
	if _gateByPlot[plotId] then
		animateGate(_gateByPlot[plotId], open)
	end
end

return BaseDoorService
