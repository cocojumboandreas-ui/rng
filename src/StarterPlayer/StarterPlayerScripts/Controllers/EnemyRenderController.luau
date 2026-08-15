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
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GridMath = require(Framework:WaitForChild("GridMath"))
local EnemyFormation = require(Framework:WaitForChild("EnemyFormation")) -- pas boczny wspolny z serwerem
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)
local PerfSettings = require(script.Parent:WaitForChild("PerfSettings")) -- panel wydajnosci

local PARK = CFrame.new(0, -500, 0)
local PREWARM = 60 -- ile modeli podstawowego wroga (tier1) prealokowac synchronicznie
local PREWARM_TIER = 10 -- ile modeli KAZDEGO innego typu tieru prealokowac (w tle)
local PREWARM_BOSS = 2 -- ile modeli KAZDEGO bossa prealokowac (w tle)
local BOSS_FOOT = 10 -- docelowy footprint bossa (study)
local GRUNT_FOOT = 4 -- docelowy footprint zwyklego wroga
-- FORMACJA (render-only): wrogowie wychodza z bramy GESIEGO/prosto, dopiero po chwili rozchodza sie na plac.
-- Cel (wg gry-wzorca): luzna MASZERUJACA LINIA przez cala szerokosc+glebokosc placu, nie zbity klab.
local LANE_SCALE = 0.9 -- rozstaw boczny (bylo 0.5 = kłąb; 0.9 = szeroki wachlarz na cala szerokosc lane)
local SPREAD_START = 0.13 -- do tego t (od bramy) ida PROSTO, gesiego (jeszcze bez rozejscia)
local SPREAD_RAMP = 0.22 -- odcinek t na ktorym narasta pelny rozstaw (t: START -> START+RAMP)
local FX_POOL = 24 -- max jednoczesnych blyskow strzalow wrogow (hitscan)
local HEAVY_CAP = 10 -- max jednoczesnych ciezkich FX (rakiety, wybuchy, ogien)
local DMG_POOL = 30 -- pula floating liczb obrazen "-N" nad wrogiem
local COIN_CAP = 48 -- max jednoczesnych monet-FX (fontanna z killa)

local RigAnimSetup = require(Framework:WaitForChild("RigAnimSetup"))
local ENEMY_ANIM = { idle = "rbxassetid://114633582166730", walk = "rbxassetid://123805470740320", shot = "rbxassetid://109739383922402" }
local ANIM_WALK_SPEED = 1.5 -- mnoznik tempa animacji chodu wroga (feet-slide fix)
local ANIM_SHOT_SPEED = 1.3 -- mnoznik tempa animacji strzalu wroga
local MOVE_SMOOTH = 16 -- tlumienie ruchu HRP (lerp/klatke); wyzej = szybciej dogania cel, mniej wygladzania

local EnemyRenderController = {}

local _folder = nil
local _fxFolder = nil
local _freeByModel = {} -- modelName -> { Model, ... }
local _active = {} -- key -> { model, modelName, plotId, isBoss, prevT, prevC, curT, curC, dir, halfH, nextFire, shown, weapon }
local _nodesByPlot = {}
local _plotCenters = {}
local _corePosByPlot = {} -- plotId -> pozycja rdzenia (WR_CoreAnchor) — cel ostrzalu gdy brak jednostki
local _focused = nil
local _lodClock = 0
local _fxFree = {} -- { {flash, tracer}, ... }
local _dmgFree = {} -- pula floating liczb obrazen "-N" (BillboardGui na anchorze)
local _coinActive = 0 -- licznik aktywnych monet-FX (cap kosztu)
local _weaponByModel = setmetatable({}, { __mode = "k" }) -- model -> { prof, part }  (bron rozpoznana raz)
local _rigByModel = setmetatable({}, { __mode = "k" }) -- model -> { kind, prof, legs/spin }  (rig anim raz)
local _hpBarByModel = setmetatable({}, { __mode = "k" }) -- model -> { gui, fill, label }  (pasek HP nad wrogiem, raz)
local _heavy = 0 -- licznik aktywnych ciezkich FX (cap kosztu)

-- pasek HP wroga (jawne HP): czerwony->zielony + liczba cur/max
local HP_RED = Color3.fromRGB(230, 55, 55)
local HP_GREEN = Color3.fromRGB(90, 225, 95)
local function shortNum(n)
	n = math.max(0, math.floor(n + 0.5))
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1000 then return string.format("%.1fK", n / 1000) end
	return tostring(n)
end

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
			-- CanQuery=true: raycast pocisku broni FPS gracza musi trafiac wroga (PlayerHitEnemy)
			d.Anchored = true; d.CanCollide = false; d.CanQuery = true; d.CanTouch = false; d.CastShadow = false
		elseif d:IsA("Humanoid") then
			-- UKRYJ domyslny napis nad glowa (modele maja zagniezdzone "Dummy" -> Roblox pisal ich nazwe).
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	local halfH = m:GetExtentsSize().Y * 0.5
	m:SetAttribute("HalfH", halfH)
	-- pasek HP nad wrogiem (raz na model, wylaczony w puli; wlaczany gdy wrog aktywny)
	do
		local w = isBoss and 120 or 56
		local gui = Instance.new("BillboardGui")
		gui.Name = "WR_EHp"
		gui.Size = UDim2.fromOffset(w, 22)
		gui.StudsOffsetWorldSpace = Vector3.new(0, halfH + (isBoss and 3 or 1.6), 0)
		gui.AlwaysOnTop = true; gui.Enabled = false; gui.Adornee = m.PrimaryPart; gui.Parent = m
		local back = Instance.new("Frame")
		back.Size = UDim2.new(1, 0, 0, isBoss and 12 or 8); back.Position = UDim2.new(0, 0, 1, isBoss and -12 or -8)
		back.BackgroundColor3 = Color3.fromRGB(20, 20, 26); back.BorderSizePixel = 0; back.Parent = gui
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1); fill.BackgroundColor3 = HP_GREEN; fill.BorderSizePixel = 0; fill.Parent = back
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 12); label.Position = UDim2.new(0, 0, 0, -1)
		label.BackgroundTransparency = 1; label.Font = Enum.Font.GothamBold
		label.TextSize = isBoss and 15 or 12; label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0.3; label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.Text = ""; label.Parent = gui
		_hpBarByModel[m] = { gui = gui, fill = fill, label = label }
	end
	_weaponByModel[m] = resolveWeapon(m, modelName) -- rozpoznaj bron raz (part przesuwa sie z modelem przez PivotTo)
	local rig = resolveRig(m, modelName) -- rozpoznaj rig anim raz (nogi/kola/wirniki)
	_rigByModel[m] = rig
	-- R6 zolnierze (kind=="walk"): PRAWDZIWE animacje (Animator) zamiast proceduralnego chodu.
	-- prepare() odkotwicza konczyny (tylko HRP zakotwiczony), spawia dodatki, dodaje Animator.
	if rig and rig.kind == "walk" then
		local animator = RigAnimSetup.prepare(m)
		if animator then
			rig.animator = animator
			rig.real = true -- tracki wczytywane LENIWIE przy 1. renderze (prewarm-load 360 naraz dawal len=0)
		end
		-- Po odkotwiczeniu rigu Humanoid RAZ wlacza Torso.CanCollide=true (silnikowo, NIE lapie Changed).
		-- Wrog tylko wizualny -> Torso niekolizyjny (pilnowane w renderStep). Torso rigu = BasePart bezposrednio
		-- pod Dummy (Humanoid.Parent); NIE FindFirstChild rekurencyjnie, bo Uniform ma pod-MODEL "Torso".
		local humB = m:FindFirstChildWhichIsA("Humanoid", true)
		local torsoPart = humB and humB.Parent and humB.Parent:FindFirstChild("Torso")
		if torsoPart and torsoPart:IsA("BasePart") then
			rig.torso = torsoPart
			rig.torso.CanCollide = false
		end
	end
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
	local rrig = _rigByModel[model]
	if rrig and rrig.real then
		if rrig.tWalk then rrig.tWalk:Stop(0) end
		if rrig.tIdle then rrig.tIdle:Stop(0) end
		if rrig.tShot then rrig.tShot:Stop(0) end
	end
	model:PivotTo(PARK)
	model:SetAttribute("WR_EnemyId", nil) -- sparkowany wrog nie moze byc trafiony przez bron FPS
	local hb = _hpBarByModel[model]
	if hb then hb.lastPct = nil; if hb.gui.Enabled then hb.gui.Enabled = false end end
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
-- efektywny cap skaluje sie budzetem PerfGovernora (niski FPS -> mniej rakiet/wybuchow naraz, min 2)
local function heavyTake()
	local cap = math.max(2, math.floor(HEAVY_CAP * PerfSettings.budget("heavy", 1)))
	if _heavy >= cap then return false end
	_heavy += 1
	return true
end
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

-- ── floating liczby obrazen "-N" (feel jak w grze-wzorcu) ──────────────────────
local function buildDmgLabel()
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.2, 0.2, 0.2); anchor.Transparency = 1
	anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false; anchor.CanTouch = false; anchor.CastShadow = false
	anchor.Parent = _fxFolder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(80, 28); gui.AlwaysOnTop = true; gui.Enabled = false; gui.Adornee = anchor; gui.Parent = anchor
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true; lbl.TextColor3 = Color3.fromRGB(255, 240, 140)
	lbl.TextStrokeTransparency = 0.25; lbl.TextStrokeColor3 = Color3.new(0, 0, 0); lbl.Text = ""; lbl.Parent = gui
	return { anchor = anchor, gui = gui, lbl = lbl }
end

-- popnij "-N" nad pozycja (rise + fade). big=trafienie krytyczne/duze -> wieksze i pomaranczowe.
local function popDamage(pos, amount, big, hs)
	local rec = table.remove(_dmgFree)
	if not rec then return end -- pula wyczerpana -> pomin (cap kosztu)
	rec.anchor.Position = pos
	rec.lbl.Text = "-" .. shortNum(amount)
	-- headshot = ZOLTY i NAJWIEKSZY; big (kryt) = pomaranczowy; zwykly = jasnozolty
	rec.lbl.TextColor3 = hs and Color3.fromRGB(255, 225, 40) or (big and Color3.fromRGB(255, 170, 60) or Color3.fromRGB(255, 240, 140))
	rec.lbl.TextTransparency = 0; rec.lbl.TextStrokeTransparency = 0.25
	rec.gui.Size = UDim2.fromOffset(hs and 150 or (big and 120 or 84), hs and 52 or (big and 42 or 30))
	local jitterX = (math.random() - 0.5) * 2.4
	rec.gui.StudsOffsetWorldSpace = Vector3.new(jitterX, 0, 0)
	rec.gui.Enabled = true
	task.spawn(function()
		local t0 = os.clock(); local dur = 0.62
		while rec.gui.Enabled do
			local a = (os.clock() - t0) / dur
			if a >= 1 then break end
			rec.gui.StudsOffsetWorldSpace = Vector3.new(jitterX, a * 3.6, 0)
			rec.lbl.TextTransparency = a * a
			rec.lbl.TextStrokeTransparency = 0.25 + a * 0.75
			RunService.Heartbeat:Wait()
		end
		rec.gui.Enabled = false
		table.insert(_dmgFree, rec)
	end)
end

-- fontanna monet z killa (kilka zlotych kulek podskakuje i znika) — bounded COIN_CAP.
-- ── HEAD SHOT: komiksowy popup przy trafieniu w glowe (czerwony burst-gwiazda + bialy napis, pop + fade) ──
local _hsActive = 0
local HS_CAP = 6 -- max jednoczesnych popupow (anty-spam przy szybkim ostrzale)
local function headshotPopup(pos)
	if _hsActive >= HS_CAP then return end
	_hsActive += 1
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.2, 0.2, 0.2); anchor.Transparency = 1
	anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false; anchor.CanTouch = false; anchor.CastShadow = false
	anchor.Position = pos; anchor.Parent = _fxFolder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(210, 92); gui.AlwaysOnTop = true; gui.Adornee = anchor; gui.Parent = anchor
	-- czerwony burst: dwa kwadraty (0deg + 45deg) = 8-ramienna gwiazda komiksu, bialy kontur
	local function star(rot)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5); f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(0.62, 0.62); f.Rotation = rot
		f.BackgroundColor3 = Color3.fromRGB(220, 30, 40); f.BorderSizePixel = 0; f.Parent = gui
		local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(255, 255, 255); st.Thickness = 3; st.Parent = f
		return f, st
	end
	local s1, s1s = star(0)
	local s2, s2s = star(45)
	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 0.5); lbl.Position = UDim2.fromScale(0.5, 0.5)
	lbl.Size = UDim2.fromScale(0.96, 0.5); lbl.Rotation = -6; lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack; lbl.TextScaled = true; lbl.TextColor3 = Color3.fromRGB(255, 225, 40) -- zolty (klasyczny headshot)
	lbl.Text = "HEAD SHOT"; lbl.TextStrokeTransparency = 0; lbl.TextStrokeColor3 = Color3.new(0, 0, 0); lbl.Parent = gui
	task.spawn(function()
		local t0 = os.clock()
		local pop, hold, rise = 0.14, 0.22, 0.44
		while anchor.Parent do
			local dt = os.clock() - t0
			local scale, fade = 1, 0
			if dt < pop then
				scale = 0.4 + (dt / pop) * 0.75 -- 0.4 -> 1.15 (overshoot)
			elseif dt < pop + hold then
				scale = 1.15 - ((dt - pop) / hold) * 0.15 -- 1.15 -> 1.0
			elseif dt < pop + hold + rise then
				local a = (dt - pop - hold) / rise
				fade = a
				gui.StudsOffsetWorldSpace = Vector3.new(0, a * 3, 0)
			else break end
			gui.Size = UDim2.fromOffset(210 * scale, 92 * scale)
			s1.BackgroundTransparency = fade; s2.BackgroundTransparency = fade
			s1s.Transparency = fade; s2s.Transparency = fade
			lbl.TextTransparency = fade; lbl.TextStrokeTransparency = fade
			RunService.Heartbeat:Wait()
		end
		anchor:Destroy()
		_hsActive -= 1
	end)
end

-- MONETY z killa: wypadaja, ladują na ziemi i KRECA sie (walec), potem MAGNES gracza sciaga je do postaci
-- (leca do gracza + kurcza sie). Realne monety liczy serwer (nagroda per fala) — to warstwa VISUAL/juice.
local COIN_IMG = "rbxassetid://79510076315488" -- ikona monety z UI (ta sama co HUD)
-- biala swietlna smuga (ogon) za moneta — jak w ref wwwr.png; najladniej podczas magnesu do gracza
local COIN_TRAIL_COL = ColorSequence.new(Color3.fromRGB(255, 255, 255))
local COIN_TRAIL_TRANS = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.4),
	NumberSequenceKeypoint.new(1, 1),
})
local COIN_TRAIL_WIDTH = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(1, 0),
})
local function addCoinTrail(part)
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.22, 0); a0.Parent = part
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.22, 0); a1.Parent = part
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0; tr.Attachment1 = a1
	tr.Color = COIN_TRAIL_COL
	tr.Transparency = COIN_TRAIL_TRANS
	tr.WidthScale = COIN_TRAIL_WIDTH
	tr.Lifetime = 0.18 -- krotki ogon
	tr.LightEmission = 0.5 -- lekka poswiata (nie oslepia)
	tr.FaceCamera = true
	tr.Parent = part
end
local function coinDrop(pos, halfH)
	local groundY = pos.Y - (halfH or 2) + 0.35
	-- liczba monet z killa skaluje sie budzetem PerfGovernora (0 na Potato = brak FX, monety i tak liczy serwer)
	local nCoins = math.floor(4 * PerfSettings.budget("coins", 1) + 0.5)
	for _ = 1, nCoins do
		if _coinActive >= COIN_CAP then return end
		_coinActive += 1
		local c = Instance.new("Part")
		c.Size = Vector3.new(0.5, 0.5, 0.5); c.Transparency = 1
		c.Anchored = true; c.CanCollide = false; c.CanQuery = false; c.CanTouch = false; c.CastShadow = false
		c.Parent = _fxFolder
		local bb = Instance.new("BillboardGui")
		bb.Adornee = c; bb.Size = UDim2.fromOffset(48, 48); bb.LightInfluence = 0
		bb.Parent = c
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(1, 1); img.BackgroundTransparency = 1; img.Image = COIN_IMG
		img.Parent = bb
			addCoinTrail(c) -- bialy ogon-smuga (kometa)
		local land = Vector3.new(pos.X + (math.random() - 0.5) * 5, groundY, pos.Z + (math.random() - 0.5) * 5)
		local p0 = pos + Vector3.new(0, 1.5, 0)
		task.spawn(function()
			local t0 = os.clock(); local d1 = 0.3 + math.random() * 0.15
			while c.Parent do
				local a = math.min((os.clock() - t0) / d1, 1)
				local p = p0:Lerp(land, a) + Vector3.new(0, math.sin(a * math.pi) * 2.2, 0)
				c.CFrame = CFrame.new(p)
				if a >= 1 then break end
				RunService.Heartbeat:Wait()
			end
			local t1 = os.clock(); local d2 = 0.35 + math.random() * 0.3
			while c.Parent and os.clock() - t1 < d2 do
				c.CFrame = CFrame.new(land)
				RunService.Heartbeat:Wait()
			end
			local from = c.Position
			local t2 = os.clock(); local d3 = 0.4
			while c.Parent do
				local a = math.min((os.clock() - t2) / d3, 1)
				local char = Players.LocalPlayer.Character
				local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
				local target = (hrp and hrp.Position + Vector3.new(0, 1.5, 0)) or from
				c.CFrame = CFrame.new(from:Lerp(target, a * a))
				local s = math.floor(48 * (1 - 0.7 * a) + 0.5) -- kurczy sie -> "wsiaka" w gracza
				bb.Size = UDim2.fromOffset(s, s)
				if a >= 1 then break end
				RunService.Heartbeat:Wait()
			end
			c:Destroy(); _coinActive = math.max(0, _coinActive - 1)
		end)
	end
end

-- wyprostuj poze trupa: nogi rowno (bez wymachu) + rece zwisaja w dol (stojaco, PRZED przewroceniem).
local function neutralPose(model)
	local pivot = model:GetPivot()
	local rig = _rigByModel[model]
	if rig and rig.real then
		if rig.tWalk then rig.tWalk:Stop(0) end
		if rig.tIdle then rig.tIdle:Stop(0) end
		if rig.tShot then rig.tShot:Stop(0) end
		return
	end
	if rig and rig.kind == "walk" and rig.legs then
		for _, leg in ipairs(rig.legs) do
			leg.part.CFrame = pivot * leg.cf
		end
	end
	local yaw = pivot.Rotation
	for _, nm in ipairs({ "Left Arm", "Right Arm" }) do
		local arm = findExact(model, nm)
		if arm then
			local top = arm.Position + arm.CFrame.UpVector * (arm.Size.Y * 0.5)
			arm.CFrame = CFrame.new(top - Vector3.new(0, arm.Size.Y * 0.5, 0)) * yaw
		end
	end
end

-- bron wypada OBOK ciala: klon czesci-broni spada na ziemie (na trupie oryginal chowamy).
local function dropWeapon(model, groundY)
	local wm = _weaponByModel[model]
	local part = wm and wm.part
	if not part or not part.Parent then return end
	local w = part:Clone()
	w.Anchored = true; w.CanCollide = false; w.CanQuery = false; w.CanTouch = false; w.CastShadow = false
	for _, d in ipairs(w:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end end
	w.Parent = _fxFolder
	part.Transparency = 1
	local from = part.Position
	local to = Vector3.new(from.X + (math.random() - 0.5) * 4, groundY + 0.3, from.Z + (math.random() - 0.5) * 4)
	task.spawn(function()
		local t0 = os.clock(); local dur = 0.45
		while w.Parent do
			local a = math.min((os.clock() - t0) / dur, 1)
			local p = from:Lerp(to, a) + Vector3.new(0, math.sin(a * math.pi) * 1.4, 0)
			w.CFrame = CFrame.new(p) * CFrame.Angles(a * 7, a * 5, a * 6)
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		task.wait(2)
		if w.Parent then w:Destroy() end
	end)
end

-- ── WRAKI POJAZDOW (jeep/czolg/heli/jet): rozbicie + ogien + dym + odlamki ──────────
local VEHICLES = { Jeep = true, Tank = true, Helicopter = true, Jet = true }
local WRECK_LIE = 3.0 -- ile sekund plonacy wrak lezy zanim zniknie

-- obroc czesc wokol punktu w swiecie (do "zlamania" lufy/wirnika bez Motor6D)
local function bendPart(part, pivotPoint, axis, angle)
	if axis.Magnitude < 1e-4 then return end
	local R = CFrame.fromAxisAngle(axis.Unit, angle)
	part.CFrame = (CFrame.new(pivotPoint) * R * CFrame.new(-pivotPoint)) * part.CFrame
end

-- odlamek (kolo/wirnik/skrzydlo) wylatuje w luku i koziolkujac laduje obok wraku
local function tossPiece(part, groundY, spread, spin)
	part.Anchored = true; part.CanCollide = false; part.CanQuery = false; part.CanTouch = false; part.CastShadow = false
	local from = part.Position
	local rotOnly = part.CFrame.Rotation
	local to = Vector3.new(from.X + (math.random() - 0.5) * spread, groundY + part.Size.Y * 0.5, from.Z + (math.random() - 0.5) * spread)
	task.spawn(function()
		local t0 = os.clock(); local dur = 0.5 + math.random() * 0.25
		while part.Parent do
			local a = math.min((os.clock() - t0) / dur, 1)
			local p = from:Lerp(to, a) + Vector3.new(0, math.sin(a * math.pi) * 2.2, 0)
			part.CFrame = CFrame.new(p) * rotOnly * CFrame.Angles(a * spin.X, a * spin.Y, a * spin.Z)
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end
	end)
end

-- podpal wrak: ogien + dym + swiatlo na korpusie (skala wg wielkosci modelu)
local function igniteWreck(clone, scale)
	local body = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
	if not body then return end
	local fire = Instance.new("Fire")
	fire.Heat = 15; fire.Size = math.clamp(scale * 0.6, 4, 20)
	fire.Color = Color3.fromRGB(255, 130, 30); fire.SecondaryColor = Color3.fromRGB(140, 45, 0)
	fire.Parent = body
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(45, 45, 45); smoke.Opacity = 0.6; smoke.RiseVelocity = 8
	smoke.Size = math.clamp(scale * 0.8, 5, 22); smoke.Parent = body
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 50); light.Brightness = 4
	light.Range = math.clamp(scale * 2, 10, 36); light.Parent = body
end

-- wygas wrak (plynnie przezroczysty + zgas ogien/swiatlo), potem usun
local function fadeWreck(clone, dur)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			TweenService:Create(d, TweenInfo.new(dur), { Transparency = 1 }):Play()
		elseif d:IsA("Fire") or d:IsA("Smoke") then
			d.Enabled = false
		elseif d:IsA("PointLight") then
			TweenService:Create(d, TweenInfo.new(dur), { Brightness = 0 }):Play()
		end
	end
	task.delay(dur + 0.15, function() if clone.Parent then clone:Destroy() end end)
end

-- polamaj czesci pojazdu wg typu (po wyladowaniu; klon nie jest juz PivotTo'wany)
local function breakVehicle(clone, modelName, groundY)
	local body = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
	local center = body and body.Position or clone:GetPivot().Position
	if modelName == "Tank" then
		local cannon = findExact(clone, "Cannon")
		if cannon then
			local dir = cannon.CFrame.LookVector
			local len = math.max(cannon.Size.X, cannon.Size.Y, cannon.Size.Z)
			local e1 = cannon.Position + dir * len * 0.5
			local e2 = cannon.Position - dir * len * 0.5
			local inner = ((e1 - center).Magnitude < (e2 - center).Magnitude) and e1 or e2
			bendPart(cannon, inner, cannon.CFrame.RightVector, math.rad(44)) -- lufa zlamana w dol
		end
		local belt = findExact(clone, "Belt") or findExact(clone, "Wheels")
		if belt then -- kawalek pekniętej gasienicy wypada obok
			local chunk = Instance.new("Part")
			chunk.Size = Vector3.new(2.4, 1.2, 5.5); chunk.Color = Color3.fromRGB(28, 28, 32); chunk.Material = Enum.Material.Metal
			local side = (math.random() > 0.5) and 1 or -1
			chunk.CFrame = belt.CFrame * CFrame.new(side * belt.Size.X * 0.5, -belt.Size.Y * 0.25, 0)
			chunk.Parent = clone
			tossPiece(chunk, groundY, 6, Vector3.new(6, 3, 4))
		end
	elseif modelName == "Helicopter" then
		local prop = findExact(clone, "Propeller")
		if prop then -- glowny wirnik zgiety + opada na korpus (zlamane smigla)
			bendPart(prop, prop.Position, prop.CFrame.LookVector, math.rad(30))
			prop.CFrame = prop.CFrame * CFrame.new(0, -0.5, 0)
		end
		local tail = findExact(clone, "BackPropeller")
		if tail then tossPiece(tail, groundY, 7, Vector3.new(9, 6, 3)) end -- wirnik ogonowy urywa sie
	elseif modelName == "Jet" then
		local dark = findExact(clone, "DarkPart") or body
		if body then -- brak osobnej czesci skrzydla -> proxy urwanego skrzydla pada obok
			local side = (math.random() > 0.5) and 1 or -1
			local wing = Instance.new("Part")
			wing.Size = Vector3.new(16, 1, 5); wing.Material = Enum.Material.Metal
			wing.Color = (dark and dark.Color) or Color3.fromRGB(70, 75, 85)
			wing.CFrame = body.CFrame * CFrame.new(side * body.Size.X * 0.3, 0, -3)
			wing.Parent = clone
			tossPiece(wing, groundY, 9, Vector3.new(4, 6, 9))
		end
	elseif modelName == "Jeep" then
		local wheel
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name:lower():find("wheel") or d.Name:lower():find("tire")) then wheel = d; break end
		end
		if wheel then tossPiece(wheel, groundY, 6, Vector3.new(10, 4, 6)) end -- kolo odpada
	end
end

-- WYBUCH pojazdu w miejscu smierci: puff Explosion (wizual, bez fizyki/dmg) + jasny blysk + fala uderzeniowa
local function vehicleExplosion(pos, scale)
	local ex = Instance.new("Explosion")
	ex.Position = pos
	ex.BlastPressure = 0 -- czysto wizualny (nie rozrzuca budowli/jednostek)
	ex.DestroyJointRadiusPercent = 0
	ex.BlastRadius = math.clamp(scale, 6, 22)
	ex.Parent = _fxFolder
	-- DZWIEK wybuchu (3D pozycyjny; wieksze pojazdy = glosniej + nizszy ton)
	local holder = Instance.new("Part")
	holder.Anchored = true; holder.CanCollide = false; holder.CanQuery = false; holder.CanTouch = false; holder.CastShadow = false
	holder.Transparency = 1; holder.Size = Vector3.one; holder.CFrame = CFrame.new(pos); holder.Parent = _fxFolder
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxassetid://3149249837" -- Cannon_Explode (Roblox)
	snd.Volume = math.clamp(0.5 + scale * 0.03, 0.5, 1)
	snd.PlaybackSpeed = math.clamp(1.15 - scale * 0.02, 0.8, 1.15)
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.RollOffMinDistance = 15; snd.RollOffMaxDistance = 260
	snd.Parent = holder
	snd:Play()
	task.delay(4.5, function() if holder.Parent then holder:Destroy() end end)
	boom(pos, Color3.fromRGB(255, 160, 50), math.clamp(scale * 0.7, 6, 16)) -- blysk + swiatlo (heavy-capped)
	if heavyTake() then -- fala uderzeniowa: plaski pierscien rozszerza sie i zanika
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CanTouch = false; ring.CastShadow = false
		ring.Material = Enum.Material.Neon; ring.Color = Color3.fromRGB(255, 190, 90); ring.Transparency = 0.2
		ring.Size = Vector3.new(0.5, 2, 2)
		ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)) -- os cylindra -> pionowo (dysk plasko)
		ring.Parent = _fxFolder
		task.spawn(function()
			local t0 = os.clock(); local dur = 0.35; local maxR = math.clamp(scale * 1.8, 10, 40)
			while ring.Parent do
				local a = math.min((os.clock() - t0) / dur, 1)
				local r = 2 + a * maxR
				ring.Size = Vector3.new(0.5, r, r); ring.Transparency = 0.2 + a * 0.8
				if a >= 1 then break end
				RunService.Heartbeat:Wait()
			end
			ring:Destroy(); heavyGive()
		end)
	end
end

-- SMIERC pojazdu: klon-wrak PLYNNIE (TweenService) rozbija sie z przechylem, pali+dymi, lamie
-- sie (lufa/wirnik/skrzydlo/kolo), lezy WRECK_LIE s i wygasa. Oryginal wraca do puli od razu.
local function vehicleWreck(e)
	local orig = e.model
	local poolKey = e.poolKey
	local halfH = e.halfH or 2
	local start = orig:GetPivot()
	local clone = orig:Clone()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
		elseif d:IsA("BillboardGui") or d:IsA("Highlight") or d:IsA("Humanoid") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy() -- zdejmij pasek HP / otoczki / napisy / skrypty
		end
	end
	clone:SetAttribute("WR_EnemyId", nil)
	if not clone.PrimaryPart then clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart") end
	clone.Parent = _fxFolder
	release(orig, poolKey) -- oryginal natychmiast do puli
	if not clone.PrimaryPart then clone:Destroy(); return end
	local ext0 = clone:GetExtentsSize()
	vehicleExplosion(start.Position, math.max(ext0.X, ext0.Y, ext0.Z)) -- WYBUCH w miejscu smierci
	-- znajdz ziemie pod wrakiem (heli/jet startuja wysoko nad ziemia)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { clone, _folder, _fxFolder }
	local hit = Workspace:Raycast(start.Position + Vector3.new(0, 2, 0), Vector3.new(0, -600, 0), rp)
	local surfaceY = hit and hit.Position.Y or (start.Position.Y - halfH)
	local _, yaw = start:ToOrientation()
	local roll = math.rad(10 + math.random() * 12) * ((math.random() > 0.5) and 1 or -1)
	local pitch = math.rad(4 + math.random() * 8)
	local groundPos = Vector3.new(start.Position.X, surfaceY + halfH * 0.9, start.Position.Z)
	local fallen = CFrame.new(groundPos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
	local flying = (e.modelName == "Helicopter" or e.modelName == "Jet")
	local dur = flying and 0.7 or 0.45
	task.spawn(function()
		local cv = Instance.new("CFrameValue"); cv.Value = start
		local conn = cv:GetPropertyChangedSignal("Value"):Connect(function()
			if clone.Parent then clone:PivotTo(cv.Value) end
		end)
		local tw = TweenService:Create(cv, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = fallen })
		tw:Play(); tw.Completed:Wait()
		conn:Disconnect(); cv:Destroy()
		if not clone.Parent then return end
		local ext = clone:GetExtentsSize()
		igniteWreck(clone, math.max(ext.X, ext.Y, ext.Z))
		breakVehicle(clone, e.modelName, surfaceY)
		task.wait(WRECK_LIE)
		if clone.Parent then fadeWreck(clone, 0.6) end
	end)
end

-- SMIERC wroga: wyprostuj poze + upusc bron, potem PLYNNIE (TweenService) padnij NA PLECY, lezy 2s, znika.
local function deathFall(e)
	local model = e.model
	local poolKey = e.poolKey
	local halfH = e.halfH or 2
	model:SetAttribute("WR_EnemyId", nil)
	local hb = _hpBarByModel[model]
	if hb then hb.lastPct = nil; if hb.gui.Enabled then hb.gui.Enabled = false end end
	local start = model:GetPivot()
	local groundY = start.Position.Y - halfH + 0.3
	neutralPose(model)
	dropWeapon(model, groundY)
	local dir = e.dir or Vector3.new(0, 0, 1)
	local fallen = CFrame.lookAlong(Vector3.new(start.Position.X, groundY, start.Position.Z), dir) * CFrame.Angles(math.rad(90), 0, 0)
	task.spawn(function()
		local cv = Instance.new("CFrameValue")
		cv.Value = start
		local conn = cv:GetPropertyChangedSignal("Value"):Connect(function()
			if model.Parent then model:PivotTo(cv.Value) end
		end)
		local tw = TweenService:Create(cv, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = fallen })
		tw:Play()
		tw.Completed:Wait()
		conn:Disconnect(); cv:Destroy()
		task.wait(2)
		release(model, poolKey)
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
-- punkt SPAWNU przy bramie bazy wroga (WR_EnemyBase) — TA SAMA logika co PlotService (serwer),
-- zeby sciezka renderu == sciezka symulacji. Wrogowie wychodza z drzwi, nie ze srodka pola.
local function gateSpawnPoint(startPos)
	local base, baseDX = nil, math.huge
	for _, b in ipairs(CollectionService:GetTagged("WR_EnemyBase")) do
		if b:IsDescendantOf(Workspace) then
			local c = b:GetBoundingBox().Position
			local dx = math.abs(c.X - startPos.X)
			if dx < baseDX then baseDX = dx; base = b end
		end
	end
	if not base then return nil end
	local baseZ = base:GetBoundingBox().Position.Z
	local sumX, sumZ, n = 0, 0, 0
	for _, ch in ipairs(base:GetChildren()) do
		if ch.Name:sub(1, 4) == "Door" then
			local p = ch:IsA("BasePart") and ch.Position or ch:GetPivot().Position
			if (startPos.Z < baseZ) == (p.Z < baseZ) then
				sumX += p.X; sumZ += p.Z; n += 1
			end
		end
	end
	if n == 0 then return nil end
	return Vector3.new(sumX / n, startPos.Y, sumZ / n)
end

local function buildNodes()
	_nodesByPlot, _plotCenters = {}, {}
	_corePosByPlot = {}
	for _, c in ipairs(CollectionService:GetTagged("WR_CoreAnchor")) do
		local pid = c:GetAttribute("PlotId")
		if pid and c:IsA("BasePart") then _corePosByPlot[pid] = c.Position end
	end
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
		-- dopnij punkt bramy jako start (spawn z drzwi) — spojne z serwerem (PlotService)
		if arr[1] then
			local gate = gateSpawnPoint(arr[1])
			if gate then table.insert(arr, 1, gate); sum += gate end
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

-- rozstaw na 9 KOLUMN placu: kazdy wrog dostaje kolumne. Kolejnosc rozproszona (krok 4 wzgl. 9)
-- => rowny wachlarz po szerokosci, a nie sweep L->P. lane = boczny offset od srodka sciezki;
-- spread narasta od bramy do pola (renderStep), wiec wychodzac z drzwi rozbiegaja sie do swoich kolumn.
local BASE_COLS = 9
local _colSeq = 0
local function laneForSpawn(isBoss: boolean): number
	if isBoss then
		return (math.random() - 0.5) * 3 -- boss trzyma sie srodka
	end
	local cs = (GameConfig.Grid and GameConfig.Grid.cellSize) or 6
	_colSeq += 1
	local col = (_colSeq * 4) % BASE_COLS -- 0..8 rozproszone, rowno pokrywa wszystkie 9 kolumn
	local center = (BASE_COLS - 1) / 2 -- 4
	local jitter = (math.random() - 0.5) * cs * 0.3 -- lekki rozrzut w kolumnie (brak idealnego nakladania)
	return (col - center) * cs * LANE_SCALE + jitter -- LANE_SCALE zwezenie -> mniejsze odleglosci
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
				model:SetAttribute("WR_EnemyId", s.id) -- do PlayerHitEnemy (bron FPS trafia ten model)
				local et = GameConfig.Wave.enemyTypes[s.typeId]
				_active[key] = {
					model = model, modelName = modelName, poolKey = poolKeyFor(modelName, s.isBoss), fullId = s.id, plotId = plotId, isBoss = s.isBoss or false,
					prevT = s.pathT, prevC = os.clock(), curT = s.pathT, curC = os.clock(),
					dir = nil, halfH = model:GetAttribute("HalfH") or 2, shown = false,
						maxHp = s.maxHp or 0, hpPct = 1, -- jawne HP: cur = maxHp * hpPct (hpPct z bufora sync)
					weapon = _weaponByModel[model], -- {prof, part} rozpoznana bron
						rig = _rigByModel[model], -- rig anim ruchu (nogi/kola/wirniki)
						-- pas boczny = KOLUMNA CELU z serwera (s.col) -> IDENTYCZNY lane co serwer (blokowanie/wyrownanie do kolumny).
						-- fallback (brak col, stary pakiet) -> deterministyczny lane z id.
						lane = s.col and EnemyFormation.laneForColumn(s.col, (GameConfig.Grid and GameConfig.Grid.width) or 9, (GameConfig.Grid and GameConfig.Grid.cellSize) or 6)
							or EnemyFormation.lane(s.id, s.isBoss, (GameConfig.Grid and GameConfig.Grid.cellSize) or 6),
						fwd = EnemyFormation.fwd(s.id, s.isBoss), -- glebokosc DETERMINISTYCZNA z id -> zgodna z serwerem
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
			if e.shown then
				coinDrop(e.model:GetPivot().Position, e.halfH) -- monety na ziemie + magnes do gracza
				if VEHICLES[e.modelName] then
					vehicleWreck(e) -- pojazd: rozbija sie, pali, dymi, lamie sie (klon; oryginal do puli od razu)
				else
					deathFall(e) -- zolnierz: pada na plecy, po 2s znika (release trzymany w deathFall)
				end
			else
				release(e.model, e.poolKey) -- niewidoczny (inny plot) -> od razu do puli
			end
			_active[key] = nil
		end
	end
end

local function onSync(_plotId, buf)
	if type(buf) ~= "buffer" then return end
	local len = buffer.len(buf)
	if len < 2 then return end -- min. sam naglowek
	local now = os.clock()
	-- FIX P0: naglowek [u8 chunkIdx][u8 chunkCount] + rekordy 4B. Chunk = NIEZALEZNA aktualizacja stanu
	-- znanych wrogow; chunkIdx/chunkCount czysto informacyjne (pruning idzie przez EnemyEvents, nie po
	-- buforze) -> stosujemy po prostu to co przyszlo, zero czekania na komplet chunkow.
	local n = (len - 2) // 4
	for i = 0, n - 1 do
		local off = 2 + i * 4
		local id = buffer.readu16(buf, off)
		local pathT = buffer.readu8(buf, off + 2) / 255
		local hpPct = buffer.readu8(buf, off + 3) / 100 -- bajt 4 = % HP (0..100)
		local e = _active[id]
		if e then
			e.prevT, e.prevC = e.curT, e.curC
			e.curT, e.curC = pathT, now
			-- floating "-N": pokaz gdy HP spadlo (tylko renderowani wrogowie -> wlasny/ogladany plot)
			local oldPct = e.hpPct or 1
			if e.shown and hpPct < oldPct - 0.004 and (e.maxHp or 0) > 0 then
				local dmg = (oldPct - hpPct) * e.maxHp
				if dmg >= 1 then
					local hp = e.model:GetPivot().Position + Vector3.new(0, (e.halfH or 2) + 1.2, 0)
					popDamage(hp, dmg, dmg >= e.maxHp * 0.25)
				end
			end
			e.hpPct = hpPct
		end
	end
end

-- echo trafienia gracza (S->C PlayerShotHit): "-N" NAD wrogiem OD RAZU, exact dmg z serwera.
-- Niezaleznie od kwantyzacji hpPct w EnemySync -> dziala tez na grubych wrogach (gdzie -N gubi sie w sync).
local function onPlayerShotHit(_plotId, id, dmg, isHead)
	if type(id) ~= "number" or type(dmg) ~= "number" or dmg < 1 then return end
	local e = _active[id % U16]
	if not e or not e.shown then return end
	local pos = e.model:GetPivot().Position + Vector3.new(0, (e.halfH or 2) + 1.2, 0)
	popDamage(pos, dmg, dmg >= (e.maxHp or 0) * 0.25, isHead) -- headshot -> zolty najwiekszy numer
	if isHead then -- HEAD SHOT: komiksowy popup nad glowa (tylko wrogowie z glowa; wykryte w kicie)
		headshotPopup(e.model:GetPivot().Position + Vector3.new(0, (e.halfH or 2) + 2.4, 0))
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

-- leniwe wczytanie tracków (raz na model, przy 1. renderze — nie w prewarm, tam len=0)
local function ensureEnemyTracks(rig)
	if not rig or not rig.animator or rig.tracksLoaded then return end
	rig.tracksLoaded = true
	local function loadTr(id, looped, prio)
		local a = Instance.new("Animation"); a.AnimationId = id
		local ok, tr = pcall(function() return rig.animator:LoadAnimation(a) end)
		if ok and tr then tr.Looped = looped; tr.Priority = prio; return tr end
		return nil
	end
	rig.tIdle = loadTr(ENEMY_ANIM.idle, true, Enum.AnimationPriority.Idle)
	rig.tWalk = loadTr(ENEMY_ANIM.walk, true, Enum.AnimationPriority.Movement)
	rig.tShot = loadTr(ENEMY_ANIM.shot, false, Enum.AnimationPriority.Action)
end

local function renderStep(dt)
	dt = dt or (1 / 60)
	local now = os.clock()
	updateFocus(now)
	local ownPlot = Players.LocalPlayer:GetAttribute("PlotId")
	-- klient-side przelaczniki wydajnosci (czytane RAZ na klatke)
	-- eff() = reczny przelacznik AND warstwa auto PerfGovernora (governor dokreca w dol przy niskim FPS)
	local sAnim = PerfSettings.eff("soldierAnim")
	local sAttack = PerfSettings.eff("attackAnim")
	local sShowOthers = PerfSettings.eff("showOthers")
	local sDmg = PerfSettings.eff("damageCounter")
	-- THROTTLING PO DYSTANSIE KAMERY: dalecy wrogowie bez animacji konczyn/bobu i bez paskow HP
	-- (z daleka i tak nieczytelne, a kosztuja CFrame/layout co klatke). Prog skaluje sie tierem governora.
	local camPos = (Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame.Position) or Vector3.zero
	local animDist = 150 * PerfSettings.budget("animDist", 1)
	local animDist2 = animDist * animDist
	for _, e in pairs(_active) do
		local own = (e.plotId == ownPlot)
		local render = own or (sShowOthers and e.plotId == _focused)
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
				-- dystans kamera->wrog (XZ): far = poza progiem -> tnij animacje/paski (ruch po sciezce zostaje)
				local dxC, dzC = pos.X - camPos.X, pos.Z - camPos.Z
				local far = (dxC * dxC + dzC * dzC) > animDist2
				local animOn = sAnim and not far

				-- ANIM ruchu + ROZSTAW: podskok/lot + offset prostopadly do sciezki (render-only)
				e.animPhase += dt
				local rig = e.rig
				local baseY = pos.Y + e.halfH
				local roll = 0
				if rig then
					local rp = rig.prof
					if rp.hoverH then -- lot: utrzymaj WYSOKOSC lotu zawsze; bujanie/przechyl tylko gdy anim ON i blisko
						baseY += rp.hoverH + (animOn and math.sin(e.animPhase * HOVER_FREQ) * (rp.bob or 0) or 0)
						if animOn and rp.bank then roll = math.sin(e.animPhase * HOVER_FREQ * 0.6) * rp.bank end
					elseif animOn and rig.kind == "walk" and not rig.real then -- marsz: podskok tulowia (procedura)
						baseY += math.abs(math.sin(e.animPhase * WALK_FREQ)) * BODY_BOB
					elseif animOn and rp.bob then -- jazda: lekki bujak (jeep/tank)
						baseY += math.abs(math.sin(e.animPhase * 11)) * rp.bob
					end
				end
				-- rozstaw NARASTA od bramy: do SPREAD_START ida PROSTO/gesiego, potem rozchodza sie na plac
				local spread = EnemyFormation.spreadAt(t) -- WSPOLNY z serwerem (zgodnosc render<->blokowanie)
				local perp = Vector3.new(-dir.Z, 0, dir.X) -- prostopadla w plaszczyznie XZ
				local wpos = Vector3.new(pos.X, baseY, pos.Z) + perp * (e.lane * spread) + dir * (e.fwd * spread)
				local pivot = CFrame.lookAlong(wpos, dir)
				if roll ~= 0 then pivot = pivot * CFrame.Angles(0, 0, roll) end
				if rig and rig.real and e.model.PrimaryPart then
					-- rusz TYLKO HRP (PivotTo nadpisalby poze Animatora); reszta welded idzie za HRP, Animator pozuje konczyny.
					-- LERP = plynny ruch/obrot (tlumi mikro-stutter); snap na 1. renderze (bez slizgu z PARK).
					local hrp = e.model.PrimaryPart
					if e.shown then
						hrp.CFrame = hrp.CFrame:Lerp(pivot, math.clamp(dt * MOVE_SMOOTH, 0, 1))
					else
						hrp.CFrame = pivot
					end
				else
					e.model:PivotTo(pivot)
				end
				e.shown = true

				-- jawne HP: pasek nad wrogiem. Aktualizuj fill/kolor/Text TYLKO gdy % faktycznie sie zmienil
				-- (TextLabel.Text = przeliczanie layoutu = drogie; wrog z pelnym HP nie przelicza co klatke).
				local hb = _hpBarByModel[e.model]
				if hb then
					if sDmg and not far then
						if not hb.gui.Enabled then hb.gui.Enabled = true end
						local pct = math.clamp(e.hpPct or 1, 0, 1)
						if hb.lastPct == nil or math.abs(pct - hb.lastPct) > 0.004 then
							hb.lastPct = pct
							hb.fill.Size = UDim2.fromScale(pct, 1)
							hb.fill.BackgroundColor3 = HP_RED:Lerp(HP_GREEN, pct)
							local mx = e.maxHp or 0
							hb.label.Text = shortNum(mx * pct) .. "/" .. shortNum(mx)
						end
					elseif hb.gui.Enabled then
						hb.gui.Enabled = false -- Damage Counter OFF -> ukryj pasek
					end
				end

				-- napedy: nogi (chod) / kola / wirniki — TYLKO gdy Soldier Animations ON i wrog BLISKO kamery
				if animOn and rig then
					if rig.kind == "walk" and not rig.real then
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

				-- wizualny ostrzal: FX pokazuj dla WLASNEGO plota zawsze; dla CUDZYCH tylko gdy attackAnim ON.
				if rig and rig.real then
					if rig.torso and rig.torso.CanCollide then rig.torso.CanCollide = false end -- gracz przechodzi przez wroga
					if animOn then
						ensureEnemyTracks(rig)
						if rig.tWalk and not rig.tWalk.IsPlaying then rig.tWalk:Play(0.25); rig.tWalk:AdjustSpeed(ANIM_WALK_SPEED) end
					else
						if rig.tWalk and rig.tWalk.IsPlaying then rig.tWalk:Stop(0.15) end
					end
				end
				if now >= e.nextFire then
					e.nextFire = now + e.atkInt * (0.8 + math.random() * 0.4)
					if own or sAttack then
						local target = nearestUnit(pos.X, pos.Z, e.atkRange)
						if not target then
							local cp = _corePosByPlot[e.plotId]
							if cp then
								local dx, dz = cp.X - pos.X, cp.Z - pos.Z
								if dx * dx + dz * dz <= e.atkRange * e.atkRange then target = cp end
							end
						end
						if target then
							local wp = e.weapon and e.weapon.part
							local muzzle
							if wp and wp.Parent then
								-- lufa przesuwa sie z modelem (PivotTo) -> jej swiatowa pozycja jest aktualna
								muzzle = wp.Position + (e.dir or dir) * 0.6
							else
								muzzle = Vector3.new(pos.X, pos.Y + e.halfH * 1.2, pos.Z)
							end
							fireWeapon(e, muzzle, target + Vector3.new(0, 1.5, 0))
						if rig and rig.real and rig.tShot then rig.tShot:Play(0.05); rig.tShot:AdjustSpeed(ANIM_SHOT_SPEED) end
						end
					end
				end
			end
		elseif e.shown then
			e.model:PivotTo(PARK)
			e.shown = false
			local prig = e.rig
			if prig and prig.real then
				if prig.tWalk then prig.tWalk:Stop(0.1) end
				if prig.tIdle then prig.tIdle:Stop(0.1) end
			end
			local hb = _hpBarByModel[e.model]
			if hb then hb.lastPct = nil; if hb.gui.Enabled then hb.gui.Enabled = false end end
		end
	end
end

function EnemyRenderController.start()
	_folder = Instance.new("Folder"); _folder.Name = "WR_EnemyRender"; _folder.Parent = Workspace
	_fxFolder = Instance.new("Folder"); _fxFolder.Name = "WR_EnemyFX"; _fxFolder.Parent = Workspace
	for _ = 1, FX_POOL do table.insert(_fxFree, buildFx()) end
	for _ = 1, DMG_POOL do table.insert(_dmgFree, buildDmgLabel()) end -- pula floating liczb obrazen
	-- FIX P0: prewarm CALY w tle (partiami po ~10) — reszta bootstrapu klienta NIE czeka na niego (kiedys 60
	-- grunta klonowanych synchronicznie = hitch przy wejsciu). Gated na Assets.Units: jesli nie zreplikowal
	-- sie w 10s, pomijamy prewarm (modele zbuduja sie leniwie przez acquire) — warn, zero erroru.
	task.spawn(function()
		local assets = ReplicatedStorage:WaitForChild("Assets", 10)
		if not assets or not assets:FindFirstChild("Units") then
			warn("[EnemyRenderController] Assets.Units niedostepny po 10s — pomijam prewarm (modele zbuduja sie leniwie)")
			return
		end
		local baseModel = enemyModelName("grunt", false)
		local baseKey = poolKeyFor(baseModel, false)
		local built = 0
		-- baza (tier1 grunt) pierwsza — pojawia sie od fali 1
		_freeByModel[baseKey] = _freeByModel[baseKey] or {}
		for _ = 1, PREWARM do
			local m = buildEnemyModel(baseModel, false)
			if m then table.insert(_freeByModel[baseKey], m) end
			built += 1
			if built % 10 == 0 then task.wait() end -- partiami po ~10, koszt klonowania rozlozony na klatki
		end
		-- pozostale tiery + bossy (osobne pule boss/zwykly) — zero Instance.new przy 1. pojawieniu w fali
		local seen = { [baseKey] = true }
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
					if built % 10 == 0 then task.wait() end
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
	Net.get("PlayerShotHit").OnClientEvent:Connect(onPlayerShotHit)
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
