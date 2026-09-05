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
local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local RigAnimSetup = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("RigAnimSetup"))
-- WR BACKUP starych anim R6 (przywroc w razie czego): idle=114633582166730  shot=109739383922402  walk=123805470740320
local ANIM_IDLE = "rbxassetid://114633582166730"
local ANIM_SHOT = "rbxassetid://109739383922402"

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

	-- ── HEAVY WEAPONS (mesh/items) — obracaja sie PRZODEM w strone wroga, strzelaja NABOJAMI (nie lasery), AoE ──
	-- aim=true -> yaw modelu sledzi cel. aimOffset (rad) koryguje os "przodu" meshu jesli art nie patrzy w -Z.
	-- kind "mg"       -> obrot + pociski-smugi z muzzle (pooled).             (MG Nest / Minigun / Dual Minigun)
	-- kind "launcher" -> obrot + SEKWENCYJNE rakiety-mesh z tub + WYBUCH AoE. (Rocket Launcher x2/x4/x6)
	-- kind "drone"    -> baza stoi; dron-mesh startuje, parabola z gory, AoE, respawn po 3s, dym silnika.
	mg_nest_a = { kind = "mg", aim = true, muzzles = 1, flash = Color3.fromRGB(255, 225, 140), bullet = Color3.fromRGB(255, 235, 150), recoil = 0.10, flashTime = 0.04 },
	mg_nest_b = { kind = "mg", aim = true, muzzles = 1, flash = Color3.fromRGB(255, 215, 120), bullet = Color3.fromRGB(255, 230, 140), recoil = 0.12, flashTime = 0.04 },
	minigun_turret = { kind = "mg", aim = true, muzzles = 1, flash = Color3.fromRGB(255, 210, 120), bullet = Color3.fromRGB(255, 225, 130), recoil = 0.06, flashTime = 0.03 },
	dual_minigun = { kind = "mg", aim = true, muzzles = 2, flash = Color3.fromRGB(255, 205, 110), bullet = Color3.fromRGB(255, 220, 120), recoil = 0.05, flashTime = 0.03 },
	rocket_launcher_x2 = { kind = "launcher", aim = true, tubes = 2, proj = Color3.fromRGB(70, 70, 70), flash = Color3.fromRGB(255, 170, 90), boom = Color3.fromRGB(255, 140, 40), boomScale = 14, recoil = 0.25, flashTime = 0.07 },
	rocket_launcher_x4 = { kind = "launcher", aim = true, tubes = 4, proj = Color3.fromRGB(70, 70, 70), flash = Color3.fromRGB(255, 170, 90), boom = Color3.fromRGB(255, 140, 40), boomScale = 16, recoil = 0.22, flashTime = 0.07 },
	rocket_launcher_x6 = { kind = "launcher", aim = true, tubes = 6, proj = Color3.fromRGB(70, 70, 70), flash = Color3.fromRGB(255, 170, 90), boom = Color3.fromRGB(255, 140, 40), boomScale = 18, recoil = 0.20, flashTime = 0.07 },
	drone_base = { kind = "drone", aim = false, boom = Color3.fromRGB(255, 150, 50), boomScale = 26, flash = Color3.fromRGB(255, 180, 90), flashTime = 0.06 },
}

local _tracked = {}
local _folder = nil
local _rangeMult = 1 -- mnoznik zasiegu ze skilli (StatsSync) — wizual dopasowany do targetingu serwera (CombatService)

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
	-- wrogowie to MODELE (WR_EnemyId ustawiony gdy zywy, wyczyszczony przy parkowaniu do puli).
	for _, m in ipairs(_folder:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("WR_EnemyId") ~= nil then
			local pos = m:GetPivot().Position
			local dx, dz = pos.X - ox, pos.Z - oz
			local d2 = dx * dx + dz * dz
			if d2 <= bestD then bestD = d2; best = pos end
		end
	end
	return best
end

-- ── efekty transientne ──────────────────────────────────────────────────────────
local function boom(pos, color, scale)
	local ball = mkNeon("WR_Boom", worldParent(), color, Enum.PartType.Ball)
	ball.Position = pos; ball.Transparency = 0.1; ball.Size = Vector3.new(1, 1, 1)
	local light = Instance.new("PointLight"); light.Color = color; light.Range = 12 + scale; light.Brightness = 6; light.Parent = ball
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

-- ── HEAVY WEAPONS: pociski proceduralne (pooling obowiazkowy) ──────────────────────
local ITEM_MODELS = ReplicatedStorage:FindFirstChild("WR_ItemModels")

-- NABOJE: krotka jasna smuga muzzle->cel, szybka. Pool wspoldzielony (miniguny sypia duzo).
local _bulletPool = {}
local function fireBullet(muzzle, target, color)
	local b = table.remove(_bulletPool)
	if not b then
		b = Instance.new("Part")
		b.Name = "WR_Bullet"; b.Anchored = true; b.CanCollide = false; b.CanQuery = false; b.CanTouch = false; b.CastShadow = false
		b.Material = Enum.Material.Neon
	end
	b.Color = color; b.Size = Vector3.new(0.45, 0.45, 3.0); b.Transparency = 0
	b.CFrame = CFrame.lookAt(muzzle, target)
	b.Parent = worldParent()
	task.spawn(function()
		local dur = math.clamp((target - muzzle).Magnitude / 260, 0.03, 0.22)
		local t0 = os.clock()
		while true do
			local a = (os.clock() - t0) / dur
			if a >= 1 then break end
			b.CFrame = CFrame.lookAt(muzzle:Lerp(target, a), target)
			RunService.Heartbeat:Wait()
		end
		b.Parent = nil
		if #_bulletPool < 64 then _bulletPool[#_bulletPool + 1] = b else b:Destroy() end
	end)
end

local function stripPhys(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false end
	end
	if inst:IsA("BasePart") then inst.Anchored = true; inst.CanCollide = false; inst.CanQuery = false; inst.CanTouch = false; inst.CastShadow = false end
end
local function place(inst, cf) if inst:IsA("Model") then inst:PivotTo(cf) else inst.CFrame = cf end end
-- os X meshy = przod (rakietka/dron 2.0 w X) -> obrot +90deg wokol Y ustawia +X w kierunek lotu (tunable).
local function noseCf(pos, look) return CFrame.lookAt(pos, look) * CFrame.Angles(0, math.rad(90), 0) end

-- RAKIETY-MESH: klon WR_RocketAmmo leci muzzle->cel lekkim lukiem, WYBUCH AoE na miejscu. Pool.
local _rocketPool = {}
local function fireRocketMesh(muzzle, target, prof)
	local r = table.remove(_rocketPool)
	if not r then
		local tmpl = ITEM_MODELS and ITEM_MODELS:FindFirstChild("WR_RocketAmmo")
		if tmpl then r = tmpl:Clone(); stripPhys(r)
		else r = Instance.new("Part"); r.Size = Vector3.new(1.6, 0.5, 0.5); r.Color = prof.proj or Color3.fromRGB(70, 70, 70); r.Material = Enum.Material.SmoothPlastic; r.Anchored = true; r.CanCollide = false; r.CanQuery = false; r.CastShadow = false end
	end
	place(r, noseCf(muzzle, target)); r.Parent = worldParent()
	task.spawn(function()
		local dur = math.clamp((target - muzzle).Magnitude / 95, 0.2, 0.7)
		local t0 = os.clock()
		local prev = muzzle
		while true do
			local a = (os.clock() - t0) / dur
			if a >= 1 then break end
			local pos = muzzle:Lerp(target, a) + Vector3.new(0, math.sin(a * math.pi) * 3, 0)
			place(r, noseCf(pos, pos + (pos - prev))); prev = pos
			RunService.Heartbeat:Wait()
		end
		r.Parent = nil
		if #_rocketPool < 24 then _rocketPool[#_rocketPool + 1] = r else r:Destroy() end
		boom(target, prof.boom or Color3.fromRGB(255, 140, 40), prof.boomScale or 6)
	end)
end

-- DRON: klon WR_DroneShahed startuje z bazy, parabola (start->apex->cel), AoE na dole, dym silnika. Pool.
local _dronePool = {}
local function launchDrone(basePos, target, prof, onDone)
	local d = table.remove(_dronePool)
	if not d then
		local tmpl = ITEM_MODELS and ITEM_MODELS:FindFirstChild("WR_DroneShahed")
		if tmpl then d = tmpl:Clone(); stripPhys(d)
		else d = Instance.new("Part"); d.Size = Vector3.new(2, 0.4, 1.6); d.Color = Color3.fromRGB(60, 60, 60); d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CastShadow = false end
		local host = d:IsA("Model") and (d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")) or d
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "WR_DroneSmoke"
		smoke.Color = ColorSequence.new(Color3.fromRGB(90, 90, 90), Color3.fromRGB(40, 40, 40))
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Lifetime = NumberRange.new(0.4, 0.7); smoke.Rate = 40; smoke.Speed = NumberRange.new(2, 4); smoke.SpreadAngle = Vector2.new(10, 10)
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2) })
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		smoke.Enabled = false; smoke.Parent = host
	end
	local host = d:IsA("Model") and (d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")) or d
	local sm = host and host:FindFirstChild("WR_DroneSmoke")
	if sm then sm.Enabled = true end
	local startP = basePos + Vector3.new(0, 2, 0)
	local apex = Vector3.new((startP.X + target.X) / 2, math.max(startP.Y, target.Y) + 42, (startP.Z + target.Z) / 2)
	place(d, noseCf(startP, apex)); d.Parent = worldParent()
	task.spawn(function()
		local dur = 1.8
		local t0 = os.clock()
		local prev = startP
		while true do
			local a = (os.clock() - t0) / dur
			if a >= 1 then break end
			local pos = startP:Lerp(apex, a):Lerp(apex:Lerp(target, a), a) -- kwadratowa bezier
			place(d, noseCf(pos, pos + (pos - prev))); prev = pos
			RunService.Heartbeat:Wait()
		end
		if sm then sm.Enabled = false end
		d.Parent = nil
		if #_dronePool < 6 then _dronePool[#_dronePool + 1] = d else d:Destroy() end
		boom(target, prof.boom or Color3.fromRGB(255, 150, 50), prof.boomScale or 7)
		if onDone then onDone() end
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

	if st.r6 and st.r6.shot then st.r6.shot:Play(0.06); st.r6.shot:AdjustSpeed(1.3) end

	if prof.kind == "flame" then
		local muzzle = (pivot * st.muzzleLocals[1]).Position
		if st.flameEmitter then
			st.flamePart.CFrame = CFrame.lookAt(muzzle, target)
			st.flameEmitter.Enabled = true
			st.flameUntil = now + 0.14
		end
		if not st.isR6 then st.recoilAmt = (prof.recoil or 0) * st.scale end
		return
	end

	if prof.kind == "rpg" then
		local muzzle = (pivot * st.muzzleLocals[1]).Position
		st.emitters[1].flash.Position = muzzle
		st.emitters[1].flash.Transparency = 0.1
		st.emitters[1].light.Brightness = 3
		st.flashUntil = now + (prof.flashTime or 0.06)
		launchProjectile(muzzle, target, prof.proj, prof.boom, 5)
		if not st.isR6 then st.recoilAmt = (prof.recoil or 0) * st.scale end
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

	if prof.kind == "mg" then
		for i, mloc in ipairs(st.muzzleLocals) do
			local muzzle = (pivot * mloc).Position
			local em = st.emitters[i]
			if em then em.flash.Position = muzzle; em.flash.Transparency = 0.15; em.light.Brightness = 2.5 end
			fireBullet(muzzle, target, prof.bullet or prof.flash)
		end
		if prof.spinBarrel then st.spinning = now + 0.15 end -- rozkrec wiazke luf
		st.flashUntil = now + (prof.flashTime or 0.04)
		if (prof.recoil or 0) > 0 then st.recoilAmt = prof.recoil * st.scale end
		return
	end

	if prof.kind == "launcher" then
		-- SEKWENCYJNIE: tuba 1, potem 2, ... z krotkim odstepem; cel-snapshot (AoE).
		if (prof.recoil or 0) > 0 then st.recoilAmt = prof.recoil * st.scale end
		for i, mloc in ipairs(st.muzzleLocals) do
			task.delay((i - 1) * 0.09, function()
				if not st.model.Parent then return end
				local muzzle = (st.model:GetPivot() * mloc).Position
				local em = st.emitters[i]
				if em then em.flash.Position = muzzle; em.flash.Transparency = 0.1; em.light.Brightness = 3; st.flashUntil = os.clock() + (prof.flashTime or 0.07) end
				fireRocketMesh(muzzle, target, prof)
			end)
		end
		return
	end

	if prof.kind == "drone" then
		if st.droneBusy then return end
		st.droneBusy = true
		local base = pivot.Position
		local em = st.emitters[1]
		if em then em.flash.Position = base; em.flash.Transparency = 0.2; em.light.Brightness = 2; st.flashUntil = now + (prof.flashTime or 0.06) end
		launchDrone(base, target, prof, function()
			task.delay(3.0, function() st.droneBusy = false end) -- respawn/gotowosc po 3s od uderzenia
		end)
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
	if (prof.recoil or 0) > 0 and not st.isR6 then st.recoilAmt = prof.recoil * st.scale end
end

-- ── petla ─────────────────────────────────────────────────────────────────────
local function step(dt)
	local now = os.clock()
	for model, st in pairs(_tracked) do
		if model.Parent then
			-- 0) AIM: wieze obracaja sie PRZODEM (-Z) w strone najblizszego wroga (yaw, plynnie)
			if st.aim then
				st.aimAcc = (st.aimAcc or 0) + dt
				if st.aimAcc >= 0.08 or st.aimTarget == nil then
					st.aimAcc = 0
					st.aimTarget = nearestEnemy(st.basePos.X, st.basePos.Z, st.range)
				end
				local tp = st.aimTarget
				if tp then
					local dx, dz = tp.X - st.basePos.X, tp.Z - st.basePos.Z
					if dx * dx + dz * dz > 1 then
						local desired = math.atan2(-dx, -dz) + (st.prof.aimOffset or 0)
						local diff = ((desired - st.yaw + math.pi) % (2 * math.pi)) - math.pi
						st.yaw += diff * math.clamp(dt * 8, 0, 1)
					end
				end
				local back = (st.recoilAmt and st.recoilAmt > 0.005) and st.recoilAmt or 0
				model:PivotTo(CFrame.new(st.basePos) * CFrame.Angles(0, st.yaw, 0) * CFrame.new(0, 0, back))
				if st.recoilAmt then st.recoilAmt *= 0.72 end
			-- 1) transform modelu: hover (heli/jet) + odrzut modelu (piechota)
			elseif st.hover then
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
			-- HEAVY minigun/dual: kreci wiazka luf wokol osi -Z przy strzale
			if st.spinners and st.spinning and now < st.spinning then
				st.barrelSpin = (st.barrelSpin or 0) + (st.prof.spin or 22) * dt
				for _, sp in ipairs(st.spinners) do
					for k, rod in ipairs(sp.rods) do
						local a = (k / 4) * 6.28318 + st.barrelSpin
						rod.CFrame = (pivot * sp.mloc) * CFrame.new(math.cos(a) * st.spinRad, math.sin(a) * st.spinRad, -0.1)
					end
				end
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

			-- 4) kadencja ognia — GOTOWY do strzalu gdy cel wejdzie w zasieg (bez czekania caly interval)
			st.acc += dt
			if st.acc >= st.interval then
				local target = nearestEnemy(pivot.Position.X, pivot.Position.Z, st.range)
				if target then st.acc = 0; fire(st, target) else st.acc = st.interval end
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
	elseif prof.kind == "mg" then
		local fy = sy * 0.42 -- wysokosc lufy (lekko w dol — naboje szly nad lufami)
		if (prof.muzzles or 1) >= 2 then
			return { CFrame.new(-sx * 0.18, fy, -(sz * 0.5 + 0.2)), CFrame.new(sx * 0.18, fy, -(sz * 0.5 + 0.2)) }
		end
		return { CFrame.new(0, fy, -(sz * 0.5 + 0.2)) }
	elseif prof.kind == "launcher" then
		local n = prof.tubes or 2
		local cols = (n <= 2) and n or math.ceil(n / 2)
		local rows = math.ceil(n / cols)
		local locs, i = {}, 0
		for r = 1, rows do
			for c = 1, cols do
				i += 1
				if i <= n then
					local tx = (cols == 1) and 0 or ((c - 1) / (cols - 1) - 0.5)
					local ty = (rows == 1) and 0 or ((r - 1) / (rows - 1) - 0.5)
					locs[i] = CFrame.new(tx * sx * 0.38, sy * 0.46 + ty * sy * 0.24, -(sz * 0.5 + 0.02)) -- siatka OTWOROW tub, na wysokosci dziur
				end
			end
		end
		return locs
	elseif prof.kind == "drone" then
		return { CFrame.new(0, sy * 0.5, 0) } -- szczyt bazy = punkt startu drona
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

	-- HEAVY minigun/dual: obracajaca sie wiazka luf (4 prety) na kazdym muzzle; kreci sie przy strzale
	if prof.spinBarrel then
		st.spinRad = sy * 0.09
		st.spinners = {}
		for _, mloc in ipairs(st.muzzleLocals) do
			local rods = {}
			for k = 1, 4 do
				local rod = Instance.new("Part")
				rod.Size = Vector3.new(sy * 0.07, sy * 0.07, sz * 0.5)
				rod.Anchored = true; rod.CanCollide = false; rod.CanQuery = false; rod.CanTouch = false; rod.CastShadow = false
				rod.Material = Enum.Material.Metal; rod.Color = Color3.fromRGB(38, 40, 44)
				local a = (k / 4) * 6.28318
				rod.CFrame = (st.baseCF * mloc) * CFrame.new(math.cos(a) * st.spinRad, math.sin(a) * st.spinRad, -0.1)
				rod.Parent = model
				rods[k] = rod
			end
			st.spinners[#st.spinners + 1] = { rods = rods, mloc = mloc }
		end
	end

	-- minigun (piechota): lufa do obrotu przy strzale. UWAGA: lufa jest odspawana+zakotwiczona na SERWERZE
	-- (BuildService.spawnModel) — inaczej wymuszanie jej CFrame walczy z RigAnimWeld i szarpie rigiem (#modele).
	if prof.kind == "minigun" then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name:lower():find("barrel") or d.Name:lower():find("minigun")) then
				st.barrel = d; st.barrelLocal = st.baseCF:ToObjectSpace(d.CFrame); st.spinAngle = 0; break
			end
		end
	end

	-- heli: wirniki ktore zawsze sie krecą (spin = LISTA rotorow; UWAGA: minigun uzywa spin=LICZBA jako predkosc lufy)
	if type(prof.spin) == "table" then
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
-- R6 jednostki gracza (zolnierze) — STACJONARNE: Idle w petli (baza) + Shot na ogniu. TYLKO te 2, z PRIORYTETAMI
-- (Idle < Action) -> nie nakladaja sie. Rig odkotwiczony server-side (BuildService RigAnimSetup.prepare -> tylko HRP
-- kotwiczony), wiec Animator klienta pozuje konczyny. Rigi z "Units Comission" poprawne -> poza nie rozwala sie.
-- isR6=true -> step() NIE dodaje proceduralnego odrzutu (soldier ma recoil>0). FX strzalu (muzzle/tracer) osobno.
local function setupR6(model)
	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	if not hum or hum.RigType ~= Enum.HumanoidRigType.R6 then return nil end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return nil end
	local function load(id, looped, prio)
		local a = Instance.new("Animation"); a.AnimationId = id
		local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
		if not ok or not tr then return nil end
		tr.Looped = looped; tr.Priority = prio
		return tr
	end
	local idle = load(ANIM_IDLE, true, Enum.AnimationPriority.Idle)
	local shot = load(ANIM_SHOT, false, Enum.AnimationPriority.Action)
	if idle then idle:Play(0.25) end -- Idle w petli
	return { idle = idle, shot = shot }
end

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
		baseRange = combat.range * (GameConfig.Sim.unitRangeMult or 1),
		range = combat.range * (GameConfig.Sim.unitRangeMult or 1) * _rangeMult, interval = 1 / math.max(combat.fireRate, 0.05),
		acc = math.random() * 0.4,
		baseCF = model:GetPivot(),
		scale = math.clamp(sz.Y / 5.5, 0.35, 1.4),
		recoilAmt = 0, recoilApplied = false,
	}
	if prof.hover then st.hover = prof.hover; st.hoverPhase = math.random() * 6.28 end
	if prof.aim then
		st.aim = true
		st.basePos = st.baseCF.Position
		local _, y0 = st.baseCF:ToEulerAnglesYXZ()
		st.yaw = y0
	end
	st.muzzleLocals = computeMuzzleLocals(prof, sz.X, sz.Y, sz.Z)
	setupFx(model, prof, st, sz.X, sz.Y, sz.Z)
	st.r6 = setupR6(model)
	st.isR6 = st.r6 ~= nil
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

	-- zasieg wizualny = baza × rangeMult ze skilli (Longer Range) -> spojnosc z targetingiem serwera.
	-- StatsSync niesie pelne staty; przy zmianie (kupno skilla) aktualizujemy zywe jednostki.
	local function applyRange(rm)
		_rangeMult = tonumber(rm) or 1
		for _, st in pairs(_tracked) do
			if st.baseRange then st.range = st.baseRange * _rangeMult end
		end
	end
	task.spawn(function()
		local ok, s = pcall(function() return Net.get("GetStats"):InvokeServer() end)
		if ok and type(s) == "table" then applyRange(s.rangeMult) end
	end)
	Net.get("StatsSync").OnClientEvent:Connect(function(s)
		if type(s) == "table" then applyRange(s.rangeMult) end
	end)

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
