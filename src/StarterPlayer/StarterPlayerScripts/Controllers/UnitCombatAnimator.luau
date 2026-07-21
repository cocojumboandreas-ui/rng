--!nonstrict
-- StarterPlayerScripts/Controllers/UnitCombatAnimator.luau  (KLIENT — kosmetyka bojowa jednostek)
-- Prawdziwa walka/dmg = serwer (CombatService). Tu TYLKO wizual: jednostki gracza "strzelaja" do
-- wrogow w zasiegu wg profilu broni, w rytmie fireRate. Piechota (faza 1-2) + pojazdy (faza 3).
--
-- RODZAJE (PROFILES[unitId].kind):
--   gun    -> muzzle flash + smuga + odrzut modelu   (Noob, Soldier, Sniper, SWAT, Jeep/kierowca)
--   minigun-> jak gun + obracajaca sie lufa           (Tank Soldier)
--   rpg    -> pocisk leci do celu + WYBUCH            (Rocket Soldier)
--   flame  -> stozek OGNIA (particle)                 (Flamethrower)
--   tank   -> dzialo: pocisk + wybuch + odrzut LUFY   (Tank)
--   heli   -> 2 miniguny + wirniki (spin) + hover     (Helicopter)
--   jet    -> lewituje (hover) + silnik (particle) + LASERY z 2 punktow (Jet)
--
-- Dane bez nowych remote'ow: WR_Units (atr. UnitId/OwnerUserId), wrogowie = Workspace.WR_EnemyRender.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local UnitCombatAnimator = {}

local PROFILES = {
	-- piechota
	noob_soldier = { kind = "gun", flash = Color3.fromRGB(255, 225, 140), tracer = Color3.fromRGB(255, 220, 120), width = 0.12, recoil = 0.18, flashTime = 0.05 },
	soldier = { kind = "gun", flash = Color3.fromRGB(255, 220, 130), tracer = Color3.fromRGB(255, 210, 90), width = 0.14, recoil = 0.15, flashTime = 0.05 },
	sniper = { kind = "gun", flash = Color3.fromRGB(180, 230, 255), tracer = Color3.fromRGB(120, 200, 255), width = 0.2, recoil = 0.34, flashTime = 0.09 },
	swat = { kind = "gun", flash = Color3.fromRGB(210, 255, 200), tracer = Color3.fromRGB(190, 255, 170), width = 0.12, recoil = 0.13, flashTime = 0.05, shield = true },
	tank_soldier = { kind = "minigun", flash = Color3.fromRGB(255, 200, 110), tracer = Color3.fromRGB(255, 180, 80), width = 0.14, recoil = 0, flashTime = 0.04, shield = true, spin = 18 },
	rocket_soldier = { kind = "rpg", flash = Color3.fromRGB(255, 170, 90), proj = Color3.fromRGB(90, 90, 90), boom = Color3.fromRGB(255, 140, 40), recoil = 0.4, flashTime = 0.08 },
	flamethrower = { kind = "flame", fire = Color3.fromRGB(255, 120, 30), recoil = 0.05 },
	-- pojazdy (faza 3)
	jeep = { kind = "gun", flash = Color3.fromRGB(255, 225, 140), tracer = Color3.fromRGB(255, 220, 120), width = 0.12, recoil = 0, flashTime = 0.05, muzzleMode = "driver" },
	tank = { kind = "tank", flash = Color3.fromRGB(255, 190, 100), tracer = Color3.fromRGB(255, 160, 60), width = 0.5, boom = Color3.fromRGB(255, 150, 50), flashTime = 0.1, cannonRecoil = 1.4 },
	helicopter = { kind = "heli", flash = Color3.fromRGB(255, 205, 120), tracer = Color3.fromRGB(255, 180, 80), width = 0.18, flashTime = 0.05, muzzles = 2,
		spin = { { name = "Propeller", axis = "Y", speed = 35 }, { name = "BackPropeller", axis = "X", speed = 28 } }, hover = { h = 4.0, bob = 0.7 } },
	jet = { kind = "jet", laser = Color3.fromRGB(255, 60, 60), width = 0.28, flashTime = 0.11, muzzles = 2, hover = { h = 6.0, bob = 0.5 }, engine = true },
}

local _tracked = {}
local _folder = nil

-- ── prymitywy ─────────────────────────────────────────────────────────────────
local function mkNeon(name, parent, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.Neon; p.Color = color; p.Transparency = 1
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

local function worldParent()
	return (_folder and _folder.Parent) or Workspace
end

local function nearestEnemy(ox, oz, range)
	if not _folder or not _folder.Parent then
		_folder = Workspace:FindFirstChild("WR_EnemyRender")
	end
	if not _folder then return nil end
	local best, bestD = nil, range * range
	for _, p in ipairs(_folder:GetChildren()) do
		if p:IsA("BasePart") and p.Transparency == 0 then
			local dx, dz = p.Position.X - ox, p.Position.Z - oz
			local d2 = dx * dx + dz * dz
			if d2 <= bestD then bestD = d2; best = p.Position end
		end
	end
	return best
end

-- ── efekty transientne ──────────────────────────────────────────────────────────
local function boom(pos, color, scale)
	local ball = mkNeon("WR_Boom", worldParent(), color, Enum.PartType.Ball)
	ball.Position = pos; ball.Transparency = 0.1; ball.Size = Vector3.new(1, 1, 1)
	local light = Instance.new("PointLight"); light.Color = color; light.Range = 16; light.Brightness = 6; light.Parent = ball
	Debris:AddItem(ball, 0.45)
	task.spawn(function()
		local t0 = os.clock()
		while ball.Parent do
			local a = (os.clock() - t0) / 0.32
			if a >= 1 then break end
			ball.Size = Vector3.one * (1 + a * scale)
			ball.Transparency = 0.1 + a * 0.9
			light.Brightness = 6 * (1 - a)
			RunService.Heartbeat:Wait()
		end
	end)
end

local function launchProjectile(muzzle, target, projColor, boomColor, boomScale)
	local rocket = mkNeon("WR_Proj", worldParent(), projColor)
	rocket.Material = Enum.Material.SmoothPlastic
	rocket.Size = Vector3.new(0.5, 0.5, 1.6); rocket.Transparency = 0
	rocket.CFrame = CFrame.lookAt(muzzle, target)
	Debris:AddItem(rocket, 1.5)
	task.spawn(function()
		local dur = math.clamp((target - muzzle).Magnitude / 110, 0.05, 0.5)
		local t0 = os.clock()
		while rocket.Parent do
			local a = (os.clock() - t0) / dur
			if a >= 1 then break end
			rocket.CFrame = CFrame.lookAt(muzzle:Lerp(target, a), target)
			RunService.Heartbeat:Wait()
		end
		if rocket.Parent then rocket:Destroy() end
		boom(target, boomColor, boomScale)
	end)
end

-- ── strzal ────────────────────────────────────────────────────────────────────
local function emitBeam(em, muzzle, target, width, color, showT)
	local dir = target - muzzle
	local len = dir.Magnitude
	em.flash.Position = muzzle
	em.flash.Transparency = 0.1
	em.light.Brightness = 3
	if len > 0.1 then
		em.tracer.Size = Vector3.new(width, width, len)
		em.tracer.CFrame = CFrame.lookAt(muzzle + dir * 0.5, target)
		em.tracer.Transparency = 0.15
	end
end

local function fire(st, target)
	local prof = st.prof
	local pivot = st.model:GetPivot()
	local now = os.clock()

	if prof.kind == "flame" then
		local muzzle = (pivot * st.muzzleLocals[1]).Position
		if st.flameEmitter then
			st.flamePart.CFrame = CFrame.lookAt(muzzle, target)
			st.flameEmitter.Enabled = true
			st.flameUntil = now + 0.14
		end
		st.recoilAmt = (prof.recoil or 0) * st.scale
		return
	end

	if prof.kind == "rpg" then
		local muzzle = (pivot * st.muzzleLocals[1]).Position
		st.emitters[1].flash.Position = muzzle
		st.emitters[1].flash.Transparency = 0.1
		st.emitters[1].light.Brightness = 3
		st.flashUntil = now + (prof.flashTime or 0.06)
		launchProjectile(muzzle, target, prof.proj, prof.boom, 5)
		st.recoilAmt = (prof.recoil or 0) * st.scale
		return
	end

	if prof.kind == "tank" then
		local muzzle = (pivot * st.muzzleLocals[1]).Position
		emitBeam(st.emitters[1], muzzle, target, prof.width, prof.tracer)
		st.flashUntil = now + (prof.flashTime or 0.1)
		boom(target, prof.boom, 4)
		if st.cannon then st.cannonRecoilAmt = (prof.cannonRecoil or 1) * st.scale end
		return
	end

	-- gun / minigun / heli / jet: strzal z KAZDEGO muzzle
	local col = prof.laser or prof.tracer
	for i, mloc in ipairs(st.muzzleLocals) do
		local muzzle = (pivot * mloc).Position
		emitBeam(st.emitters[i], muzzle, target, prof.width, col)
	end
	st.flashUntil = now + (prof.flashTime or 0.05)
	if prof.kind == "minigun" then st.spinning = now + 0.12 end
	if (prof.recoil or 0) > 0 then st.recoilAmt = prof.recoil * st.scale end
end

-- ── petla ─────────────────────────────────────────────────────────────────────
local function step(dt)
	local now = os.clock()
	for model, st in pairs(_tracked) do
		if model.Parent then
			-- 1) transform modelu: hover (heli/jet) + odrzut modelu (piechota)
			if st.hover then
				st.hoverPhase += dt * 2.2
				local y = (st.hover.h + math.sin(st.hoverPhase) * st.hover.bob) * st.scale
				local back = (st.recoilAmt and st.recoilAmt > 0.005) and st.recoilAmt or 0
				model:PivotTo(st.baseCF * CFrame.new(0, y, back))
				if st.recoilAmt then st.recoilAmt *= 0.72 end
			elseif st.recoilAmt and st.recoilAmt > 0.005 then
				model:PivotTo(st.baseCF - st.baseCF.LookVector * st.recoilAmt)
				st.recoilAmt *= 0.72
				st.recoilApplied = true
			elseif st.recoilApplied then
				model:PivotTo(st.baseCF)
				st.recoilApplied = false
			end
			local pivot = model:GetPivot()

			-- 2) wirniki heli (zawsze), lufa miniguna (przy strzale), odrzut lufy czolgu
			if st.spinParts then
				for _, sp in ipairs(st.spinParts) do
					sp.angle = (sp.angle + sp.speed * dt) % (math.pi * 2)
					sp.part.CFrame = pivot * sp.local_ * sp.rot(sp.angle)
				end
			end
			if st.barrel and st.spinning and now < st.spinning then
				st.spinAngle = (st.spinAngle + st.prof.spin * dt) % (math.pi * 2)
				st.barrel.CFrame = pivot * st.barrelLocal * CFrame.Angles(0, 0, st.spinAngle)
			end
			if st.cannon then
				if st.cannonRecoilAmt and st.cannonRecoilAmt > 0.01 then
					st.cannon.CFrame = pivot * st.cannonLocal * CFrame.new(0, 0, st.cannonRecoilAmt)
					st.cannonRecoilAmt *= 0.8
				else
					st.cannon.CFrame = pivot * st.cannonLocal
				end
			end

			-- 3) wygas flash/tracer/ogien
			if st.flashUntil and now >= st.flashUntil then
				for _, em in ipairs(st.emitters or {}) do
					em.flash.Transparency = 1; em.light.Brightness = 0; em.tracer.Transparency = 1
				end
				st.flashUntil = nil
			end
			if st.flameUntil and now >= st.flameUntil then
				if st.flameEmitter then st.flameEmitter.Enabled = false end
				st.flameUntil = nil
			end

			-- 4) kadencja ognia
			st.acc += dt
			if st.acc >= st.interval then
				st.acc = 0
				local target = nearestEnemy(pivot.Position.X, pivot.Position.Z, st.range)
				if target then fire(st, target) end
			end
		end
	end
end

-- ── setup ─────────────────────────────────────────────────────────────────────
local function mkEmitter(model, flashColor, tracerColor, width)
	local flash = mkNeon("WR_Muzzle", model, flashColor, Enum.PartType.Ball)
	flash.Size = Vector3.new(0.7, 0.7, 0.7)
	local light = Instance.new("PointLight"); light.Color = flashColor; light.Range = 8; light.Brightness = 0; light.Parent = flash
	local tracer = mkNeon("WR_Tracer", model, tracerColor)
	tracer.Size = Vector3.new(width, width, 1)
	return { flash = flash, light = light, tracer = tracer }
end

local ROT = {
	X = function(a) return CFrame.Angles(a, 0, 0) end,
	Y = function(a) return CFrame.Angles(0, a, 0) end,
	Z = function(a) return CFrame.Angles(0, 0, a) end,
}

local function computeMuzzleLocals(prof, sx, sy, sz)
	if prof.muzzleMode == "driver" then
		return { CFrame.new(-sx * 0.22, sy * 0.15, -sz * 0.28) }
	elseif prof.kind == "tank" then
		return { CFrame.new(0, sy * 0.12, -(sz * 0.5 + 0.5)) }
	elseif prof.kind == "heli" then
		return { CFrame.new(-sx * 0.35, -sy * 0.05, -sz * 0.3), CFrame.new(sx * 0.35, -sy * 0.05, -sz * 0.3) }
	elseif prof.kind == "jet" then
		return { CFrame.new(-sx * 0.32, 0, -sz * 0.42), CFrame.new(sx * 0.32, 0, -sz * 0.42) }
	end
	return { CFrame.new(0, sy * 0.12, -(sz * 0.5 + 0.4)) } -- pojedynczy przod
end

local function setupFx(model, prof, st, sx, sy, sz)
	if prof.kind == "flame" then
		local part = mkNeon("WR_FlameMuzzle", model, prof.fire)
		part.Size = Vector3.new(0.5, 0.5, 0.5)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 200, 60), Color3.fromRGB(220, 40, 10))
		emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
		emitter.Lifetime = NumberRange.new(0.25, 0.4); emitter.Rate = 120
		emitter.Speed = NumberRange.new(14, 22); emitter.SpreadAngle = Vector2.new(12, 12)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.5) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		emitter.EmissionDirection = Enum.NormalId.Front; emitter.Acceleration = Vector3.new(0, 6, 0)
		emitter.Enabled = false; emitter.Parent = part
		st.flamePart = part; st.flameEmitter = emitter
		return
	end

	-- emittery per muzzle
	local col = prof.tracer or prof.laser or prof.flash
	st.emitters = {}
	for _ = 1, #st.muzzleLocals do
		st.emitters[#st.emitters + 1] = mkEmitter(model, prof.flash or col, col, prof.width or 0.14)
	end

	-- minigun (piechota): lufa do obrotu przy strzale
	if prof.kind == "minigun" then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name:lower():find("barrel") or d.Name:lower():find("minigun")) then
				st.barrel = d; st.barrelLocal = st.baseCF:ToObjectSpace(d.CFrame); st.spinAngle = 0; break
			end
		end
	end

	-- heli: wirniki ktore zawsze sie krecą
	if prof.spin then
		st.spinParts = {}
		for _, spec in ipairs(prof.spin) do
			local part = model:FindFirstChild(spec.name, true)
			if part and part:IsA("BasePart") then
				st.spinParts[#st.spinParts + 1] = {
					part = part, speed = spec.speed, angle = 0,
					local_ = st.baseCF:ToObjectSpace(part.CFrame), rot = ROT[spec.axis] or ROT.Y,
				}
			end
		end
	end

	-- tank: lufa do odrzutu
	if prof.kind == "tank" then
		local cannon = model:FindFirstChild("Cannon", true)
		if cannon and cannon:IsA("BasePart") then
			st.cannon = cannon; st.cannonLocal = st.baseCF:ToObjectSpace(cannon.CFrame)
		end
	end

	-- jet: silnik (particle) z tylu (+Z)
	if prof.engine then
		local part = mkNeon("WR_Engine", model, Color3.fromRGB(120, 180, 255))
		part.Size = Vector3.new(1, 1, 1)
		part.CFrame = st.baseCF * CFrame.new(0, 0, sz * 0.4)
		local em = Instance.new("ParticleEmitter")
		em.Color = ColorSequence.new(Color3.fromRGB(150, 210, 255), Color3.fromRGB(60, 90, 200))
		em.Texture = "rbxasset://textures/particles/fire_main.dds"
		em.Lifetime = NumberRange.new(0.2, 0.35); em.Rate = 90
		em.Speed = NumberRange.new(10, 16); em.SpreadAngle = Vector2.new(8, 8)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2.6) })
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		em.EmissionDirection = Enum.NormalId.Back; em.Parent = part
		st.engineEmitter = em
	end
end

-- ── track/untrack ───────────────────────────────────────────────────────────────
local function track(model)
	if _tracked[model] then return end
	if model:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then return end
	local unitId = model:GetAttribute("UnitId")
	if not unitId then return end
	local prof = PROFILES[unitId]
	local combat = GameConfig.Units[unitId] and GameConfig.Units[unitId].combat
	if not prof or not combat then return end

	local _, sz = model:GetBoundingBox()
	local st = {
		model = model, prof = prof,
		range = combat.range, interval = 1 / math.max(combat.fireRate, 0.05),
		acc = math.random() * 0.4,
		baseCF = model:GetPivot(),
		scale = math.clamp(sz.Y / 5.5, 0.35, 1.4),
		recoilAmt = 0, recoilApplied = false,
	}
	if prof.hover then st.hover = prof.hover; st.hoverPhase = math.random() * 6.28 end
	st.muzzleLocals = computeMuzzleLocals(prof, sz.X, sz.Y, sz.Z)
	setupFx(model, prof, st, sz.X, sz.Y, sz.Z)
	_tracked[model] = st
end

local function untrack(model)
	_tracked[model] = nil
end

local function bindFolder(units)
	for _, m in ipairs(units:GetChildren()) do
		if m:IsA("Model") then track(m) end
	end
	units.ChildAdded:Connect(function(m)
		if m:IsA("Model") then task.defer(track, m) end
	end)
	units.ChildRemoved:Connect(untrack)
end

function UnitCombatAnimator.start()
	RunService.Heartbeat:Connect(step)
	local existing = Workspace:FindFirstChild("WR_Units")
	if existing then
		bindFolder(existing)
	else
		task.spawn(function() bindFolder(Workspace:WaitForChild("WR_Units")) end)
	end
end

function UnitCombatAnimator._StateForTest()
	local n = 0
	for _ in pairs(_tracked) do n += 1 end
	return { tracked = n }
end

return UnitCombatAnimator
