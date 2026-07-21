--!nonstrict
-- StarterPlayerScripts/Controllers/EnemyRenderController.luau  (§9 — klient, FAZA 4: prawdziwe modele)
-- Renderuje wrogow jako PRAWDZIWE modele (Assets.Units wg enemyType.model), przeskalowane, zwrocone
-- w kierunku marszu, stopami na sciezce. EnemyEvents (reliable)=spawn/death, EnemySync (unreliable)=pathT.
-- Modele POOLowane per nazwa modelu (zero Instance.new w trakcie fali po prewarm). LOD: pelny render
-- tylko plot WLASNY + OGLADANY kamera (reszta parkowana poza ekranem).
-- FAZA 4: wrogowie wizualnie STRZELAJA do najblizszej jednostki gracza w zasiegu (muzzle+smuga, pula FX).
-- Realne obrazenia jednostek (HP, smierc) = FAZA 5.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GridMath = require(Framework:WaitForChild("GridMath"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local PARK = CFrame.new(0, -500, 0)
local PREWARM = 60 -- ile modeli podstawowego wroga prealokowac
local BOSS_FOOT = 10 -- docelowy footprint bossa (study)
local GRUNT_FOOT = 4 -- docelowy footprint zwyklego wroga
local FX_POOL = 24 -- max jednoczesnych blyskow strzalow wrogow

local EnemyRenderController = {}

local _folder = nil
local _fxFolder = nil
local _freeByModel = {} -- modelName -> { Model, ... }
local _active = {} -- key -> { model, modelName, plotId, isBoss, prevT, prevC, curT, curC, dir, halfH, nextFire, shown }
local _nodesByPlot = {}
local _plotCenters = {}
local _focused = nil
local _lodClock = 0
local _fxFree = {} -- { {flash, tracer}, ... }

-- ── model wroga: prawdziwy z Assets.Units, przeskalowany + statyczny ─────────────
local function enemyModelName(typeId, isBoss)
	local et = GameConfig.Wave.enemyTypes[typeId]
	return (et and et.model) or "Noob Soldier"
end

local function buildEnemyModel(modelName, isBoss): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local uf = assets and assets:FindFirstChild("Units")
	local tmpl = uf and uf:FindFirstChild(modelName)
	if not tmpl then
		return nil
	end
	local m = tmpl:Clone()
	if not m.PrimaryPart then
		local hrp = m:FindFirstChild("HumanoidRootPart")
		if hrp then
			m.PrimaryPart = hrp
		else
			local big, bv = nil, -1
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					local v = d.Size.X * d.Size.Y * d.Size.Z
					if v > bv then bv, big = v, d end
				end
			end
			m.PrimaryPart = big
		end
	end
	m:PivotTo(CFrame.new(0, 0, 0))
	local size = m:GetExtentsSize()
	local target = isBoss and BOSS_FOOT or GRUNT_FOOT
	local factor = math.min(target / math.max(size.X, 0.01), target / math.max(size.Z, 0.01))
	if m.ScaleTo and factor < 0.999 then m:ScaleTo(factor) end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
		end
	end
	m:SetAttribute("HalfH", m:GetExtentsSize().Y * 0.5)
	m:PivotTo(PARK)
	m.Parent = _folder
	return m
end

local function acquire(modelName, isBoss): Model?
	local pool = _freeByModel[modelName]
	local m = pool and table.remove(pool)
	if not m then
		m = buildEnemyModel(modelName, isBoss)
	end
	return m
end

local function release(model, modelName)
	if not model then return end
	model:PivotTo(PARK)
	_freeByModel[modelName] = _freeByModel[modelName] or {}
	table.insert(_freeByModel[modelName], model)
end

-- ── pula FX strzalow wrogow ─────────────────────────────────────────────────────
local function buildFx()
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball; flash.Size = Vector3.new(0.6, 0.6, 0.6)
	flash.Anchored = true; flash.CanCollide = false; flash.CanQuery = false; flash.CanTouch = false; flash.CastShadow = false
	flash.Material = Enum.Material.Neon; flash.Color = Color3.fromRGB(255, 120, 90); flash.Transparency = 1
	flash.Parent = _fxFolder
	local tracer = Instance.new("Part")
	tracer.Size = Vector3.new(0.12, 0.12, 1)
	tracer.Anchored = true; tracer.CanCollide = false; tracer.CanQuery = false; tracer.CanTouch = false; tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon; tracer.Color = Color3.fromRGB(255, 130, 90); tracer.Transparency = 1
	tracer.Parent = _fxFolder
	return { flash = flash, tracer = tracer }
end

local function fireAt(fromPos, toPos)
	local fx = table.remove(_fxFree)
	if not fx then return end -- pula wyczerpana -> pomin (cap kosztu)
	fx.flash.Position = fromPos; fx.flash.Transparency = 0.1
	local dir = toPos - fromPos
	local len = dir.Magnitude
	if len > 0.1 then
		fx.tracer.Size = Vector3.new(0.12, 0.12, len)
		fx.tracer.CFrame = CFrame.lookAt(fromPos + dir * 0.5, toPos)
		fx.tracer.Transparency = 0.2
	end
	task.delay(0.06, function()
		fx.flash.Transparency = 1; fx.tracer.Transparency = 1
		table.insert(_fxFree, fx)
	end)
end

-- najblizsza jednostka gracza w zasiegu (XZ)
local function nearestUnit(ox, oz, range)
	local units = Workspace:FindFirstChild("WR_Units")
	if not units then return nil end
	local best, bestD = nil, range * range
	for _, m in ipairs(units:GetChildren()) do
		if m:IsA("Model") and m.PrimaryPart then
			local p = m:GetPivot().Position
			local dx, dz = p.X - ox, p.Z - oz
			local d2 = dx * dx + dz * dz
			if d2 <= bestD then bestD = d2; best = p end
		end
	end
	return best
end

-- ── geometria z tagow ────────────────────────────────────────────────────────────
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
			arr[#arr + 1] = e.pos; sum += e.pos
		end
		_nodesByPlot[pid] = arr
		_plotCenters[pid] = #arr > 0 and sum / #arr or Vector3.zero
	end
end

-- ── remote handlers ──────────────────────────────────────────────────────────────
local U16 = 65536

local function hasNodes(): boolean
	return next(_nodesByPlot) ~= nil
end

local function onEvents(payload)
	if not hasNodes() then buildNodes() end
	local plotId = payload.plotId
	for _, s in ipairs(payload.spawns or {}) do
		local key = s.id % U16
		local existing = _active[key]
		if existing and existing.fullId ~= s.id then
			release(existing.model, existing.modelName)
			_active[key] = nil
		end
		if not _active[key] then
			local modelName = enemyModelName(s.typeId, s.isBoss)
			local model = acquire(modelName, s.isBoss)
			if model then
				local et = GameConfig.Wave.enemyTypes[s.typeId]
				_active[key] = {
					model = model, modelName = modelName, fullId = s.id, plotId = plotId, isBoss = s.isBoss or false,
					prevT = s.pathT, prevC = os.clock(), curT = s.pathT, curC = os.clock(),
					dir = nil, halfH = model:GetAttribute("HalfH") or 2, shown = false,
					atkRange = et and et.atkRange or 14, atkInt = et and et.atkRate and (1 / et.atkRate) or 1.5,
					nextFire = os.clock() + math.random() * 1.5,
				}
			end
		end
	end
	for _, id in ipairs(payload.deaths or {}) do
		local key = id % U16
		local e = _active[key]
		if e then
			release(e.model, e.modelName)
			_active[key] = nil
		end
	end
end

local function onSync(_plotId, buf)
	if type(buf) ~= "buffer" then return end
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

-- ── LOD ──────────────────────────────────────────────────────────────────────────
local function updateFocus(now)
	if now - _lodClock < 0.2 then return end
	_lodClock = now
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local best, bestScore = nil, 0.5
	for pid, center in pairs(_plotCenters) do
		local dir = center - cam.CFrame.Position
		if dir.Magnitude > 1 then
			local score = cam.CFrame.LookVector:Dot(dir.Unit)
			if score > bestScore then bestScore, best = score, pid end
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
				-- kierunek marszu (styczna sciezki) -> zwrot modelu
				local ahead = GridMath.polylinePos(nodes, math.min(t + 0.02, 1))
				local d = ahead - pos
				if d.Magnitude > 0.01 then e.dir = d.Unit end
				local dir = e.dir or Vector3.new(0, 0, 1)
				e.model:PivotTo(CFrame.lookAlong(Vector3.new(pos.X, pos.Y + e.halfH, pos.Z), dir))
				e.shown = true

				-- FAZA 4: wizualny ostrzal najblizszej jednostki gracza
				if now >= e.nextFire then
					e.nextFire = now + e.atkInt * (0.8 + math.random() * 0.4)
					local u = nearestUnit(pos.X, pos.Z, e.atkRange)
					if u then
						fireAt(Vector3.new(pos.X, pos.Y + e.halfH * 1.2, pos.Z), u + Vector3.new(0, 1.5, 0))
					end
				end
			end
		elseif e.shown then
			e.model:PivotTo(PARK)
			e.shown = false
		end
	end
end

function EnemyRenderController.start()
	_folder = Instance.new("Folder"); _folder.Name = "WR_EnemyRender"; _folder.Parent = Workspace
	_fxFolder = Instance.new("Folder"); _fxFolder.Name = "WR_EnemyFX"; _fxFolder.Parent = Workspace
	for _ = 1, FX_POOL do table.insert(_fxFree, buildFx()) end
	-- prewarm modelu podstawowego wroga
	local baseModel = enemyModelName("grunt", false)
	_freeByModel[baseModel] = {}
	for _ = 1, PREWARM do
		local m = buildEnemyModel(baseModel, false)
		if m then table.insert(_freeByModel[baseModel], m) end
	end
	buildNodes()
	CollectionService:GetInstanceAddedSignal("WR_PathNode"):Connect(buildNodes)
	task.spawn(function()
		for _ = 1, 50 do
			if hasNodes() then break end
			task.wait(0.2); buildNodes()
		end
	end)
	Net.get("EnemyEvents").OnClientEvent:Connect(onEvents)
	Net.get("EnemySync").OnClientEvent:Connect(onSync)
	RunService.RenderStepped:Connect(renderStep)
end

-- Hooki testowe.
function EnemyRenderController._RenderOnceForTest()
	renderStep()
end
function EnemyRenderController._StatsForTest()
	local active, shown = 0, 0
	for _, e in pairs(_active) do
		active += 1
		if e.shown then shown += 1 end
	end
	local free = 0
	for _, pool in pairs(_freeByModel) do free += #pool end
	return { active = active, shown = shown, free = free, focused = _focused }
end

return EnemyRenderController
