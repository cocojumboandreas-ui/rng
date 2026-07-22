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
local PREWARM = 60 -- ile modeli podstawowego wroga (tier1) prealokowac synchronicznie
local PREWARM_TIER = 10 -- ile modeli KAZDEGO innego typu tieru prealokowac (w tle)
local PREWARM_BOSS = 2 -- ile modeli KAZDEGO bossa prealokowac (w tle)
local BOSS_FOOT = 10 -- docelowy footprint bossa (study)
local GRUNT_FOOT = 4 -- docelowy footprint zwyklego wroga
local FX_POOL = 24 -- max jednoczesnych blyskow strzalow wrogow (hitscan)
local HEAVY_CAP = 10 -- max jednoczesnych ciezkich FX (rakiety, wybuchy, ogien)

local EnemyRenderController = {}

local _folder = nil
local _fxFolder = nil
local _freeByModel = {} -- modelName -> { Model, ... }
local _active = {} -- key -> { model, modelName, plotId, isBoss, prevT, prevC, curT, curC, dir, halfH, nextFire, shown, weapon }
local _nodesByPlot = {}
local _plotCenters = {}
local _focused = nil
local _lodClock = 0
local _fxFree = {} -- { {flash, tracer}, ... }
local _weaponByModel = setmetatable({}, { __mode = "k" }) -- model -> { prof, part }  (bron rozpoznana raz)
local _rigByModel = setmetatable({}, { __mode = "k" }) -- model -> { kind, prof, legs/spin }  (rig anim raz)
local _heavy = 0 -- licznik aktywnych ciezkich FX (cap kosztu)

-- stale animacji ruchu
local WALK_FREQ = 9 -- czestotliwosc kroku (rad/s)
local LEG_AMP = 0.5 -- amplituda wymachu nogi (rad)
local BODY_BOB = 0.16 -- podskok tulowia (study) przy marszu
local HOVER_FREQ = 2.4 -- czestotliwosc bujania lotu/jazdy

-- ── profile broni per model wroga (muzzle = nazwa czesci-lufy w modelu) ──────────
-- kind: gun (hitscan) | minigun (jak gun) | rpg (pocisk+wybuch) | flame (ogien) | tank (dzialo+wybuch)
local WEAPON = {
	["Noob Soldier"] = { kind = "gun", muzzle = { "Pistol" }, flash = Color3.fromRGB(255, 225, 140), tracer = Color3.fromRGB(255, 220, 120), width = 0.12, flashTime = 0.05 },
	["Soldier"] = { kind = "gun", muzzle = { "ShotPart", "Rifle", "Handle" }, flash = Color3.fromRGB(255, 220, 130), tracer = Color3.fromRGB(255, 210, 90), width = 0.14, flashTime = 0.05 },
	["SWAT"] = { kind = "gun", muzzle = { "ShotPart", "Pistol", "Handle" }, flash = Color3.fromRGB(210, 255, 200), tracer = Color3.fromRGB(190, 255, 170), width = 0.12, flashTime = 0.05 },
	["Sniper"] = { kind = "gun", muzzle = { "ShotPart", "Scope", "Sniper", "Handle" }, flash = Color3.fromRGB(180, 230, 255), tracer = Color3.fromRGB(120, 200, 255), width = 0.2, flashTime = 0.09 },
	["Flamethrower"] = { kind = "flame", muzzle = { "Support", "Handle" } },
	["FlameThrower"] = { kind = "flame", muzzle = { "RedPart", "Support", "Handle" } },
	["Rocket Soldier"] = { kind = "rpg", muzzle = { "Rocket", "RPG", "Handle" }, flash = Color3.fromRGB(255, 170, 90), proj = Color3.fromRGB(90, 90, 90), boom = Color3.fromRGB(255, 140, 40), flashTime = 0.08 },
	["Tank Soldier"] = { kind = "minigun", muzzle = { "GunBarrel", "Minigun" }, flash = Color3.fromRGB(255, 200, 110), tracer = Color3.fromRGB(255, 180, 80), width = 0.14, flashTime = 0.04 },
	["Tank"] = { kind = "tank", muzzle = { "Cannon" }, flash = Color3.fromRGB(255, 190, 100), tracer = Color3.fromRGB(255, 160, 60), width = 0.5, boom = Color3.fromRGB(255, 150, 50), flashTime = 0.1 },
	["Helicopter"] = { kind = "minigun", muzzle = { "MiniGun", "Guns" }, flash = Color3.fromRGB(255, 205, 120), tracer = Color3.fromRGB(255, 180, 80), width = 0.18, flashTime = 0.05 },
	["Jet"] = { kind = "gun", muzzle = { "MainPart" }, flash = Color3.fromRGB(255, 90, 90), tracer = Color3.fromRGB(255, 60, 60), width = 0.28, flashTime = 0.11 },
}
local DEFAULT_WEAPON = { kind = "gun", muzzle = {}, flash = Color3.fromRGB(255, 120, 90), tracer = Color3.fromRGB(255, 130, 90), width = 0.12, flashTime = 0.06 }

-- znajdz czesc-lufe w modelu (po nazwie z profilu) -> profil + part (raz na model)
local function resolveWeapon(model, modelName)
	local prof = WEAPON[modelName] or DEFAULT_WEAPON
	local part = nil
	for _, nm in ipairs(prof.muzzle) do
		local lnm = nm:lower()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:lower() == lnm then part = d; break end
		end
		if part then break end
	end
	return { prof = prof, part = part }
end

-- ── profile animacji ruchu per model wroga ────────────────────────────────────────
-- walk: wymach nog + podskok tulowia (rece+bron statyczne -> bron zostaje w rekach)
-- wheels: obrot kol + lekki bujak (jeep/tank)   fly: hover + wirniki/przechyl (heli/jet)
local ROT = {
	X = function(a) return CFrame.Angles(a, 0, 0) end,
	Y = function(a) return CFrame.Angles(0, a, 0) end,
	Z = function(a) return CFrame.Angles(0, 0, a) end,
}
local ANIM = {
	["Noob Soldier"] = { kind = "walk" },
	["Soldier"] = { kind = "walk" },
	["SWAT"] = { kind = "walk" },
	["Sniper"] = { kind = "walk" },
	["Flamethrower"] = { kind = "walk" },
	["FlameThrower"] = { kind = "walk" },
	["Rocket Soldier"] = { kind = "walk" },
	["Tank Soldier"] = { kind = "walk" },
	["Jeep"] = { kind = "wheels", bob = 0.12, spin = { { contains = "wheel", axis = "X", speed = 16 } } },
	["Tank"] = { kind = "wheels", bob = 0.05, spin = { { contains = "wheel", axis = "X", speed = 9 } } },
	["Helicopter"] = { kind = "fly", hoverH = 6, bob = 0.6, spin = { { name = "Propeller", axis = "Y", speed = 40 }, { name = "BackPropeller", axis = "X", speed = 32 } } },
	["Jet"] = { kind = "fly", hoverH = 8, bob = 0.5, bank = 0.16 },
}

local function findExact(model, name)
	local ln = name:lower()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower() == ln then return d end
	end
	return nil
end

-- rozpoznaj rig anim raz na model (offsety wzgledem pivota -> rig sztywny, wazny w kazdej pozycji)
local function resolveRig(model, modelName)
	local prof = ANIM[modelName]
	if not prof then return nil end
	local pivot = model:GetPivot()
	local rig = { kind = prof.kind, prof = prof }
	if prof.kind == "walk" then
		rig.legs = {}
		for i, nm in ipairs({ "Left Leg", "Right Leg" }) do
			local p = findExact(model, nm)
			if p then
				rig.legs[#rig.legs + 1] = { part = p, cf = pivot:ToObjectSpace(p.CFrame), half = p.Size.Y * 0.5, phase = (i == 1) and 0 or math.pi }
			end
		end
	else
		rig.spin = {}
		for _, spec in ipairs(prof.spin or {}) do
			local rot = ROT[spec.axis] or ROT.X
			if spec.name then
				local p = findExact(model, spec.name)
				if p then rig.spin[#rig.spin + 1] = { part = p, cf = pivot:ToObjectSpace(p.CFrame), rot = rot, speed = spec.speed } end
			elseif spec.contains then
				local c = spec.contains:lower()
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d.Name:lower():find(c) then
						rig.spin[#rig.spin + 1] = { part = d, cf = pivot:ToObjectSpace(d.CFrame), rot = rot, speed = spec.speed }
					end
				end
			end
		end
	end
	return rig
end

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
	_weaponByModel[m] = resolveWeapon(m, modelName) -- rozpoznaj bron raz (part przesuwa sie z modelem przez PivotTo)
	_rigByModel[m] = resolveRig(m, modelName) -- rozpoznaj rig anim raz (nogi/kola/wirniki)
	m:PivotTo(PARK)
	m.Parent = _folder
	return m
end

-- pule ROZDZIELONE boss/zwykly: ten sam model (Tank/Heli/Jet) jest i tierem (skala 4) i bossem
-- (skala 10) -> osobne pule, inaczej boss wziąłby maly model z puli zwyklych.
local function poolKeyFor(modelName, isBoss)
	return isBoss and (modelName .. "#boss") or modelName
end

local function acquire(modelName, isBoss): Model?
	local key = poolKeyFor(modelName, isBoss)
	local pool = _freeByModel[key]
	local m = pool and table.remove(pool)
	if not m then
		m = buildEnemyModel(modelName, isBoss)
	end
	return m
end

local function release(model, poolKey)
	if not model then return end
	model:PivotTo(PARK)
	_freeByModel[poolKey] = _freeByModel[poolKey] or {}
	table.insert(_freeByModel[poolKey], model)
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

-- ── ciezkie FX (rakiety/wybuchy/ogien) z twardym capem ────────────────────────────
local function heavyTake() if _heavy >= HEAVY_CAP then return false end _heavy += 1 return true end
local function heavyGive() _heavy = math.max(0, _heavy - 1) end

local function boom(pos, color, scale)
	if not heavyTake() then return end
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball; ball.Anchored = true; ball.CanCollide = false; ball.CanQuery = false; ball.CanTouch = false; ball.CastShadow = false
	ball.Material = Enum.Material.Neon; ball.Color = color; ball.Transparency = 0.1; ball.Size = Vector3.one; ball.Position = pos; ball.Parent = _fxFolder
	local light = Instance.new("PointLight"); light.Color = color; light.Range = 14; light.Brightness = 5; light.Parent = ball
	task.spawn(function()
		local t0 = os.clock()
		while ball.Parent do
			local a = (os.clock() - t0) / 0.3
			if a >= 1 then break end
			ball.Size = Vector3.one * (1 + a * scale); ball.Transparency = 0.1 + a * 0.9; light.Brightness = 5 * (1 - a)
			RunService.Heartbeat:Wait()
		end
		ball:Destroy(); heavyGive()
	end)
end

local function rpgShot(muzzle, target, prof)
	local fx = table.remove(_fxFree) -- blysk lufy (pooled)
	if fx then
		fx.flash.Color = prof.flash or Color3.fromRGB(255, 170, 90); fx.flash.Position = muzzle; fx.flash.Transparency = 0.1
		task.delay(prof.flashTime or 0.08, function() fx.flash.Transparency = 1; fx.tracer.Transparency = 1; table.insert(_fxFree, fx) end)
	end
	if not heavyTake() then boom(target, prof.boom or Color3.fromRGB(255, 140, 40), 5); return end
	local rocket = Instance.new("Part")
	rocket.Anchored = true; rocket.CanCollide = false; rocket.CanQuery = false; rocket.CanTouch = false; rocket.CastShadow = false
	rocket.Material = Enum.Material.SmoothPlastic; rocket.Color = prof.proj or Color3.fromRGB(90, 90, 90)
	rocket.Size = Vector3.new(0.5, 0.5, 1.6); rocket.CFrame = CFrame.lookAt(muzzle, target); rocket.Parent = _fxFolder
	task.spawn(function()
		local dur = math.clamp((target - muzzle).Magnitude / 110, 0.05, 0.5)
		local t0 = os.clock()
		while rocket.Parent do
			local a = (os.clock() - t0) / dur
			if a >= 1 then break end
			rocket.CFrame = CFrame.lookAt(muzzle:Lerp(target, a), target); RunService.Heartbeat:Wait()
		end
		rocket:Destroy(); heavyGive(); boom(target, prof.boom or Color3.fromRGB(255, 140, 40), 5)
	end)
end

local function flameBurst(muzzle, target)
	if not heavyTake() then return end
	local part = Instance.new("Part")
	part.Anchored = true; part.CanCollide = false; part.CanQuery = false; part.CanTouch = false; part.CastShadow = false
	part.Transparency = 1; part.Size = Vector3.new(0.5, 0.5, 0.5); part.CFrame = CFrame.lookAt(muzzle, target); part.Parent = _fxFolder
	local em = Instance.new("ParticleEmitter")
	em.Color = ColorSequence.new(Color3.fromRGB(255, 200, 60), Color3.fromRGB(220, 40, 10))
	em.Texture = "rbxasset://textures/particles/fire_main.dds"
	em.Lifetime = NumberRange.new(0.2, 0.35); em.Rate = 0; em.Speed = NumberRange.new(14, 22); em.SpreadAngle = Vector2.new(12, 12)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.2) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	em.EmissionDirection = Enum.NormalId.Front; em.Acceleration = Vector3.new(0, 6, 0); em.Parent = part
	em:Emit(18)
	task.delay(0.45, function() part:Destroy(); heavyGive() end)
end

-- strzal wroga: muzzle = swiatowa pozycja lufy, per rodzaj broni
local function fireWeapon(e, muzzle, target)
	local prof = (e.weapon and e.weapon.prof) or DEFAULT_WEAPON
	local k = prof.kind
	if k == "flame" then flameBurst(muzzle, target); return end
	if k == "rpg" then rpgShot(muzzle, target, prof); return end
	-- gun / minigun / tank: hitscan blysk+smuga z puli, kolor per bron
	local fx = table.remove(_fxFree)
	if not fx then return end -- pula wyczerpana -> pomin (cap kosztu)
	fx.flash.Color = prof.flash; fx.flash.Position = muzzle; fx.flash.Transparency = 0.1
	local dir = target - muzzle
	local len = dir.Magnitude
	if len > 0.1 then
		local w = prof.width or 0.12
		fx.tracer.Color = prof.tracer; fx.tracer.Size = Vector3.new(w, w, len)
		fx.tracer.CFrame = CFrame.lookAt(muzzle + dir * 0.5, target); fx.tracer.Transparency = 0.15
	end
	if k == "tank" then boom(target, prof.boom or Color3.fromRGB(255, 150, 50), 4) end
	task.delay(prof.flashTime or 0.06, function()
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
			release(existing.model, existing.poolKey)
			_active[key] = nil
		end
		if not _active[key] then
			local modelName = enemyModelName(s.typeId, s.isBoss)
			local model = acquire(modelName, s.isBoss)
			if model then
				local et = GameConfig.Wave.enemyTypes[s.typeId]
				_active[key] = {
					model = model, modelName = modelName, poolKey = poolKeyFor(modelName, s.isBoss), fullId = s.id, plotId = plotId, isBoss = s.isBoss or false,
					prevT = s.pathT, prevC = os.clock(), curT = s.pathT, curC = os.clock(),
					dir = nil, halfH = model:GetAttribute("HalfH") or 2, shown = false,
					weapon = _weaponByModel[model], -- {prof, part} rozpoznana bron
						rig = _rigByModel[model], -- rig anim ruchu (nogi/kola/wirniki)
						lane = (((s.id) % 3) - 1) * 2.6, -- rozstaw w bok (3 kolumny) — nie gesiego
						fwd = (((s.id) % 5) - 2) * 1.4, -- rozstaw w glab (stagger rzedow)
						animPhase = math.random() * 6.28, -- desync animacji
						atkRange = et and et.atkRange or 14,
						atkInt = et and et.atkRate and (1 / et.atkRate) or 1.5,
					nextFire = os.clock() + math.random() * 1.5,
				}
			end
		end
	end
	for _, id in ipairs(payload.deaths or {}) do
		local key = id % U16
		local e = _active[key]
		if e then
			release(e.model, e.poolKey)
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

local function renderStep(dt)
	dt = dt or (1 / 60)
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

				-- ANIM ruchu + ROZSTAW: podskok/lot + offset prostopadly do sciezki (render-only)
				e.animPhase += dt
				local rig = e.rig
				local baseY = pos.Y + e.halfH
				local roll = 0
				if rig then
					local rp = rig.prof
					if rp.hoverH then -- lot (heli/jet)
						baseY += rp.hoverH + math.sin(e.animPhase * HOVER_FREQ) * (rp.bob or 0)
						if rp.bank then roll = math.sin(e.animPhase * HOVER_FREQ * 0.6) * rp.bank end
					elseif rig.kind == "walk" then -- marsz: podskok tulowia
						baseY += math.abs(math.sin(e.animPhase * WALK_FREQ)) * BODY_BOB
					elseif rp.bob then -- jazda: lekki bujak (jeep/tank)
						baseY += math.abs(math.sin(e.animPhase * 11)) * rp.bob
					end
				end
				local perp = Vector3.new(-dir.Z, 0, dir.X) -- prostopadla w plaszczyznie XZ
				local wpos = Vector3.new(pos.X, baseY, pos.Z) + perp * e.lane + dir * e.fwd
				local pivot = CFrame.lookAlong(wpos, dir)
				if roll ~= 0 then pivot = pivot * CFrame.Angles(0, 0, roll) end
				e.model:PivotTo(pivot)
				e.shown = true

				-- napedy: nogi (chod, przeciwfaza) / kola / wirniki
				if rig then
					if rig.kind == "walk" then
						for _, leg in ipairs(rig.legs) do
							local s = math.sin(e.animPhase * WALK_FREQ + leg.phase) * LEG_AMP
							leg.part.CFrame = pivot * leg.cf * (CFrame.new(0, leg.half, 0) * CFrame.Angles(s, 0, 0) * CFrame.new(0, -leg.half, 0))
						end
					elseif rig.spin then
						for _, sp in ipairs(rig.spin) do
							sp.part.CFrame = pivot * sp.cf * sp.rot((e.animPhase * sp.speed) % (math.pi * 2))
						end
					end
				end

				-- FAZA 4: wizualny ostrzal najblizszej jednostki gracza
				if now >= e.nextFire then
					e.nextFire = now + e.atkInt * (0.8 + math.random() * 0.4)
					local u = nearestUnit(pos.X, pos.Z, e.atkRange)
					if u then
						local wp = e.weapon and e.weapon.part
						local muzzle
						if wp and wp.Parent then
							-- lufa przesuwa sie z modelem (PivotTo) -> jej swiatowa pozycja jest aktualna
							muzzle = wp.Position + (e.dir or dir) * 0.6
						else
							muzzle = Vector3.new(pos.X, pos.Y + e.halfH * 1.2, pos.Z)
						end
						fireWeapon(e, muzzle, u + Vector3.new(0, 1.5, 0))
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
	-- prewarm bazowego wroga (tier1) synchronicznie — pojawia sie od fali 1
	local baseModel = enemyModelName("grunt", false)
	local baseKey = poolKeyFor(baseModel, false)
	_freeByModel[baseKey] = {}
	for _ = 1, PREWARM do
		local m = buildEnemyModel(baseModel, false)
		if m then table.insert(_freeByModel[baseKey], m) end
	end
	-- prewarm pozostalych modeli tierow + bossow W TLE (rozlozony na klatki), osobne pule boss/zwykly.
	-- Zero Instance.new przy pierwszym pojawieniu Snipera/Heli/Jeta w fali (brak hitcha).
	task.spawn(function()
		local seen = { [baseKey] = true }
		local built = 0
		for _, et in pairs(GameConfig.Wave.enemyTypes) do
			local isBoss = et.isBoss or false
			local modelName = et.model or baseModel
			local pk = poolKeyFor(modelName, isBoss)
			if not seen[pk] then
				seen[pk] = true
				local count = isBoss and PREWARM_BOSS or PREWARM_TIER
				_freeByModel[pk] = _freeByModel[pk] or {}
				for _ = 1, count do
					local m = buildEnemyModel(modelName, isBoss)
					if m then table.insert(_freeByModel[pk], m) end
					built += 1
					if built % 8 == 0 then task.wait() end -- rozloz koszt klonowania na klatki
				end
			end
		end
	end)
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
