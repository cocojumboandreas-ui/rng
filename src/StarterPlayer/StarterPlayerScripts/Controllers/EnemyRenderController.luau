--!nonstrict
-- StarterPlayerScripts/Controllers/EnemyRenderController.luau  (§9 — klient)
-- Renderuje wrogow: EnemyEvents (reliable) = spawn/death, EnemySync (unreliable) = pozycje pathT.
-- Wrog wizualny = lekki placeholder Part (anchored, CanCollide/CanQuery/CanTouch=false, BEZ Humanoida),
-- OBJECT-POOLED (zero Instance.new w trakcie fali). MODEL-AGNOSTIC: wizual tworzy JEDNA fabryka
-- (createEnemyVisual) — podmiana docelowego meshu wroga = zmiana tylko tam, bez ruszania render/LOD/pool.
-- LOD od dnia zero: pelny render tylko plot WLASNY + plot OGLADANY kamera; reszta ukryta (Transparency=1).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GridMath = require(Framework:WaitForChild("GridMath"))

local POOL_SIZE = 360 -- 300 (bramka) + zapas; pool prealokowany -> zero Instance.new w fali
local PARK = Vector3.new(0, -500, 0)
local Y_OFFSET = 1.5 -- podstawa wroga nad sciezka

-- ── MODEL-AGNOSTIC wizual (JEDNO miejsce) ──────────────────────────────────────
local ENEMY_VISUAL = { size = Vector3.new(2, 3, 2), color = Color3.fromRGB(200, 40, 40), material = Enum.Material.SmoothPlastic }
local function createEnemyVisual(): BasePart
	local p = Instance.new("Part")
	p.Size = ENEMY_VISUAL.size
	p.Color = ENEMY_VISUAL.color
	p.Material = ENEMY_VISUAL.material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local EnemyRenderController = {}

local _folder = nil
local _free = {} -- pula wolnych partow
local _active = {} -- enemyId -> {part, plotId, prevT, prevC, curT, curC}
local _nodesByPlot = {} -- plotId -> {Vector3,...}
local _plotCenters = {} -- plotId -> Vector3
local _focused = nil
local _lodClock = 0

-- ── pool ──
local function acquire(): BasePart
	local part = table.remove(_free)
	if not part then
		part = createEnemyVisual() -- awaryjnie (pool wyczerpany) — nie powinno przy POOL_SIZE>300
		part.Parent = _folder
	end
	part.Transparency = 0
	return part
end
local function release(part: BasePart)
	part.Transparency = 1
	part.Position = PARK
	table.insert(_free, part)
end

-- ── geometria z tagow (mapa zreplikowana) ──
local function buildNodes()
	_nodesByPlot, _plotCenters = {}, {}
	local tmp = {}
	for _, n in ipairs(CollectionService:GetTagged("WR_PathNode")) do
		local pid = n:GetAttribute("PlotId")
		if pid then
			tmp[pid] = tmp[pid] or {}
			table.insert(tmp[pid], { ord = n:GetAttribute("Order") or 0, pos = n.Position })
		end
	end
	for pid, list in pairs(tmp) do
		table.sort(list, function(a, b) return a.ord < b.ord end)
		local arr, sum = {}, Vector3.zero
		for _, e in ipairs(list) do
			arr[#arr + 1] = e.pos
			sum += e.pos
		end
		_nodesByPlot[pid] = arr
		_plotCenters[pid] = #arr > 0 and sum / #arr or Vector3.zero
	end
end

-- ── remote handlers ──
local U16 = 65536 -- id klucz = fullId % U16 (ta sama przestrzen co u16 w EnemySync)

local function hasNodes(): boolean
	return next(_nodesByPlot) ~= nil
end

local function onEvents(payload)
	if not hasNodes() then
		buildNodes() -- leniwa odbudowa (tagi mogly dojsc po init kliencie)
	end
	local plotId = payload.plotId
	for _, s in ipairs(payload.spawns or {}) do
		local key = s.id % U16 -- klucz u16 spojny z EnemySync
		local existing = _active[key]
		if existing then
			if existing.fullId ~= s.id then
				-- kolizja u16 (nie powinna: alive/plot ~50, id monotoniczne, zycie sekundy)
				warn(("[EnemyRender] kolizja u16 id=%d (fullId %d vs %d) — rozwaz u32/per-plot id"):format(key, existing.fullId, s.id))
				release(existing.part)
				_active[key] = nil
			end -- inaczej: duplikat spawnu tego samego wroga -> ignoruj
		end
		if not _active[key] then
			_active[key] = { part = acquire(), fullId = s.id, plotId = plotId, prevT = s.pathT, prevC = os.clock(), curT = s.pathT, curC = os.clock() }
		end
	end
	for _, id in ipairs(payload.deaths or {}) do
		local key = id % U16
		local e = _active[key]
		if e then
			release(e.part)
			_active[key] = nil
		end
	end
end

-- EnemySync: (plotId, buffer) — 4B/wrog: u16 id(id%65536), u8 pathT(0..255), u8 hpPct.
local function onSync(_plotId, buf)
	if type(buf) ~= "buffer" then
		return
	end
	local now = os.clock()
	local n = buffer.len(buf) // 4
	for i = 0, n - 1 do
		local off = i * 4
		local id = buffer.readu16(buf, off)
		local pathT = buffer.readu8(buf, off + 2) / 255
		local e = _active[id]
		if e then
			e.prevT, e.prevC = e.curT, e.curC
			e.curT, e.curC = pathT, now
		end
	end
end

-- ── LOD: plot ogladany kamera (throttled ~5 Hz) ──
local function updateFocus(now)
	if now - _lodClock < 0.2 then
		return
	end
	_lodClock = now
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local best, bestScore = nil, 0.5
	for pid, center in pairs(_plotCenters) do
		local dir = center - cam.CFrame.Position
		if dir.Magnitude > 1 then
			local score = cam.CFrame.LookVector:Dot(dir.Unit)
			if score > bestScore then
				bestScore, best = score, pid
			end
		end
	end
	_focused = best
end

local function renderStep()
	local now = os.clock()
	updateFocus(now)
	local ownPlot = Players.LocalPlayer:GetAttribute("PlotId")
	for _, e in pairs(_active) do
		local render = (e.plotId == ownPlot) or (e.plotId == _focused)
		if render then
			local nodes = _nodesByPlot[e.plotId]
			if nodes then
				local span = e.curC - e.prevC
				local alpha = span > 0 and math.clamp((now - e.curC) / span, 0, 1) or 1
				local t = e.prevT + (e.curT - e.prevT) * alpha
				local pos = GridMath.polylinePos(nodes, t)
				if e.part.Transparency ~= 0 then
					e.part.Transparency = 0
				end
				e.part.Position = Vector3.new(pos.X, pos.Y + Y_OFFSET, pos.Z)
			end
		elseif e.part.Transparency ~= 1 then
			e.part.Transparency = 1 -- LOD: ukryj wrogow spoza wlasnego/ogladanego plotu
		end
	end
end

function EnemyRenderController.start()
	_folder = Instance.new("Folder")
	_folder.Name = "WR_EnemyRender"
	_folder.Parent = Workspace
	for i = 1, POOL_SIZE do
		local p = createEnemyVisual()
		p.Transparency = 1
		p.Position = PARK
		p.Parent = _folder
		_free[i] = p
	end
	buildNodes()
	-- tagi mapy moga dojsc po starcie klienta: dobuduj przy pojawieniu wezla i w petli-retry
	CollectionService:GetInstanceAddedSignal("WR_PathNode"):Connect(buildNodes)
	task.spawn(function()
		for _ = 1, 50 do
			if hasNodes() then
				break
			end
			task.wait(0.2)
			buildNodes()
		end
	end)
	Net.get("EnemyEvents").OnClientEvent:Connect(onEvents)
	Net.get("EnemySync").OnClientEvent:Connect(onSync)
	RunService.RenderStepped:Connect(renderStep)
end

-- Hooki TYLKO do testow (client eval).
function EnemyRenderController._RenderOnceForTest()
	renderStep()
end
function EnemyRenderController._StatsForTest()
	local active, visible = 0, 0
	for _, e in pairs(_active) do
		active += 1
		if e.part.Transparency == 0 then
			visible += 1
		end
	end
	return { active = active, visible = visible, free = #_free, focused = _focused, plotsWithNodes = (function()
		local n = 0
		for _ in pairs(_nodesByPlot) do n += 1 end
		return n
	end)() }
end

return EnemyRenderController
