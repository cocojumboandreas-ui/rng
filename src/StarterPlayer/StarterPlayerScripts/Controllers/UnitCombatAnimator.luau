--!nonstrict
-- StarterPlayerScripts/Controllers/UnitCombatAnimator.luau  (KLIENT — kosmetyka bojowa jednostek)
-- Prawdziwa walka/dmg = serwer (CombatService). Tu TYLKO wizual: postawione jednostki gracza
-- "strzelaja" do wrogow w zasiegu wg profilu broni, w rytmie fireRate.
--
-- RODZAJE broni (PROFILES[unitId].kind):
--   gun      -> muzzle flash + smuga (tracer) + odrzut         (Noob/Pistol, Soldier/Rifle, Sniper, SWAT/Rifle)
--   minigun  -> jak gun + OBRACAJACA sie lufa, szybkie naboje    (Tank Soldier)
--   rpg      -> pocisk leci do celu + WYBUCH na trafieniu         (Rocket Soldier)
--   flame    -> stozek OGNIA (particle) na krotki zasieg          (Flamethrower)
-- Tarcza (profil.shield) = jednostka trzyma tarcze (juz w modelu) — wizualnie obronna.
--
-- Dane bez nowych remote'ow: jednostki = Workspace.WR_Units (atr. UnitId/OwnerUserId),
-- wrogowie = pozycje z Workspace.WR_EnemyRender (widoczne Party). Animujemy tylko jednostki gracza (LOD).
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
	noob_soldier = { kind = "gun", flash = Color3.fromRGB(255, 225, 140), tracer = Color3.fromRGB(255, 220, 120), width = 0.12, recoil = 0.18, flashTime = 0.05 },
	soldier = { kind = "gun", flash = Color3.fromRGB(255, 220, 130), tracer = Color3.fromRGB(255, 210, 90), width = 0.14, recoil = 0.15, flashTime = 0.05 },
	sniper = { kind = "gun", flash = Color3.fromRGB(180, 230, 255), tracer = Color3.fromRGB(120, 200, 255), width = 0.2, recoil = 0.34, flashTime = 0.09 },
	swat = { kind = "gun", flash = Color3.fromRGB(210, 255, 200), tracer = Color3.fromRGB(190, 255, 170), width = 0.12, recoil = 0.13, flashTime = 0.05, shield = true },
	tank_soldier = { kind = "minigun", flash = Color3.fromRGB(255, 200, 110), tracer = Color3.fromRGB(255, 180, 80), width = 0.14, recoil = 0, flashTime = 0.04, shield = true, spin = 18 },
	rocket_soldier = { kind = "rpg", flash = Color3.fromRGB(255, 170, 90), proj = Color3.fromRGB(90, 90, 90), boom = Color3.fromRGB(255, 140, 40), recoil = 0.4, flashTime = 0.08 },
	flamethrower = { kind = "flame", fire = Color3.fromRGB(255, 120, 30), recoil = 0.05 },
}

local _tracked = {}
local _folder = nil

-- ── prymitywy FX ────────────────────────────────────────────────────────────────
local function mkNeon(name, parent, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.Neon; p.Color = color; p.Transparency = 1
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

-- ── cele ─────────────────────────────────────────────────────────────────────────
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

local function muzzleOf(st)
	local pivot = st.baseCF
	return pivot.Position + pivot.LookVector * st.reach + Vector3.new(0, st.chest, 0)
end

-- ── efekty transientne (task.spawn, krotkie, niskiej czestotliwosci) ──────────────
local function boom(pos, color, scale)
	local ball = mkNeon("WR_Boom", _folder and _folder.Parent or Workspace, color, Enum.PartType.Ball)
	ball.Position = pos; ball.Transparency = 0.1; ball.Size = Vector3.new(1, 1, 1)
	local light = Instance.new("PointLight"); light.Color = color; light.Range = 14; light.Brightness = 5; light.Parent = ball
	Debris:AddItem(ball, 0.4)
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local a = (os.clock() - t0) / 0.3
			if a >= 1 or not ball.Parent then break end
			ball.Size = Vector3.one * (1 + a * scale)
			ball.Transparency = 0.1 + a * 0.9
			light.Brightness = 5 * (1 - a)
			RunService.Heartbeat:Wait()
		end
	end)
end

local function launchRocket(st, muzzle, target)
	local prof = st.prof
	local rocket = mkNeon("WR_Rocket", _folder and _folder.Parent or Workspace, prof.proj)
	rocket.Material = Enum.Material.SmoothPlastic
	rocket.Size = Vector3.new(0.4, 0.4, 1.4); rocket.Transparency = 0
	rocket.CFrame = CFrame.lookAt(muzzle, target)
	Debris:AddItem(rocket, 1.2)
	task.spawn(function()
		local dist = (target - muzzle).Magnitude
		local speed = 90
		local dur = math.clamp(dist / speed, 0.06, 0.5)
		local t0 = os.clock()
		while true do
			local a = (os.clock() - t0) / dur
			if a >= 1 or not rocket.Parent then break end
			rocket.CFrame = CFrame.lookAt(muzzle:Lerp(target, a), target)
			RunService.Heartbeat:Wait()
		end
		if rocket.Parent then rocket:Destroy() end
		boom(target, prof.boom, 5) -- leciutki wybuch
	end)
end

-- ── strzal wg rodzaju ─────────────────────────────────────────────────────────────
local function fire(st, target)
	local prof = st.prof
	local muzzle = muzzleOf(st)
	local now = os.clock()

	if prof.kind == "flame" then
		-- stozek ognia: wlacz emiter na chwile (przy fireRate~3 wyglada ciagle)
		if st.flameEmitter then
			st.flamePart.CFrame = CFrame.lookAt(muzzle, target)
			st.flameEmitter.Enabled = true
			st.flameUntil = now + 0.14
		end
		st.recoilAmt = prof.recoil * st.scale
		return
	end

	-- muzzle flash (wspolny dla gun/minigun/rpg)
	st.fx.flash.Position = muzzle
	st.fx.flash.Transparency = 0.1
	st.fx.light.Brightness = 3
	st.flashUntil = now + (prof.flashTime or 0.05)

	if prof.kind == "rpg" then
		launchRocket(st, muzzle, target)
	else
		-- gun/minigun: smuga do celu
		local dir = target - muzzle
		local len = dir.Magnitude
		if len > 0.1 then
			st.fx.tracer.Size = Vector3.new(prof.width, prof.width, len)
			st.fx.tracer.CFrame = CFrame.lookAt(muzzle + dir * 0.5, target)
			st.fx.tracer.Transparency = 0.15
		end
		if prof.kind == "minigun" then
			st.spinning = now + 0.12 -- utrzymaj obrot lufy chwile po strzale
		end
	end
	st.recoilAmt = prof.recoil * st.scale
end

-- ── petla ─────────────────────────────────────────────────────────────────────────
local function step(dt)
	local now = os.clock()
	for model, st in pairs(_tracked) do
		if model.Parent then
			-- odrzut calego modelu (gun/rpg); minigun ma recoil=0
			if st.recoilAmt and st.recoilAmt > 0.005 then
				model:PivotTo(st.baseCF - st.baseCF.LookVector * st.recoilAmt)
				st.recoilAmt *= 0.72
				st.recoilApplied = true
			elseif st.recoilApplied then
				model:PivotTo(st.baseCF)
				st.recoilApplied = false
			end

			-- wygas flash/tracer
			if st.flashUntil and now >= st.flashUntil then
				st.fx.flash.Transparency = 1; st.fx.light.Brightness = 0
				st.fx.tracer.Transparency = 1
				st.flashUntil = nil
			end
			-- wygas ogien
			if st.flameUntil and now >= st.flameUntil then
				if st.flameEmitter then st.flameEmitter.Enabled = false end
				st.flameUntil = nil
			end
			-- obrot lufy miniguna
			if st.barrel and st.spinning and now < st.spinning then
				st.spinAngle = (st.spinAngle + st.prof.spin * dt) % (math.pi * 2)
				st.barrel.CFrame = st.baseCF * st.barrelLocal * CFrame.Angles(0, 0, st.spinAngle)
			end

			-- kadencja ognia
			st.acc += dt
			if st.acc >= st.interval then
				st.acc = 0
				local target = nearestEnemy(st.baseCF.Position.X, st.baseCF.Position.Z, st.range)
				if target then fire(st, target) end
			end
		end
	end
end

-- ── setup FX per jednostka ────────────────────────────────────────────────────────
local function findBarrel(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = d.Name:lower()
			if n:find("barrel") or n:find("minigun") then return d end
		end
	end
	return nil
end

local function setupFx(model, prof, st)
	if prof.kind == "flame" then
		local part = mkNeon("WR_FlameMuzzle", model, prof.fire)
		part.Transparency = 1; part.Size = Vector3.new(0.5, 0.5, 0.5)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 200, 60), Color3.fromRGB(220, 40, 10))
		emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
		emitter.Lifetime = NumberRange.new(0.25, 0.4)
		emitter.Rate = 120
		emitter.Speed = NumberRange.new(14, 22)
		emitter.SpreadAngle = Vector2.new(12, 12)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.5) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		emitter.EmissionDirection = Enum.NormalId.Front
		emitter.Acceleration = Vector3.new(0, 6, 0)
		emitter.Enabled = false
		emitter.Parent = part
		st.flamePart = part; st.flameEmitter = emitter
		return
	end
	-- gun/minigun/rpg: flash + light + (tracer dla gun/minigun)
	local flash = mkNeon("WR_Muzzle", model, prof.flash, Enum.PartType.Ball)
	flash.Size = Vector3.new(0.7, 0.7, 0.7)
	local light = Instance.new("PointLight"); light.Color = prof.flash; light.Range = 8; light.Brightness = 0; light.Parent = flash
	local tracer = mkNeon("WR_Tracer", model, prof.tracer or prof.flash)
	tracer.Size = Vector3.new(prof.width or 0.12, prof.width or 0.12, 1)
	st.fx = { flash = flash, light = light, tracer = tracer }

	if prof.kind == "minigun" then
		local barrel = findBarrel(model)
		if barrel then
			st.barrel = barrel
			st.barrelLocal = st.baseCF:ToObjectSpace(barrel.CFrame)
			st.spinAngle = 0
		end
	end
end

-- ── track/untrack ─────────────────────────────────────────────────────────────────
local function track(model)
	if _tracked[model] then return end
	if model:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then return end
	local unitId = model:GetAttribute("UnitId")
	if not unitId then return end
	local prof = PROFILES[unitId]
	local combat = GameConfig.Units[unitId] and GameConfig.Units[unitId].combat
	if not prof or not combat then return end -- brak profilu/broni (np. blok/tarcza-only) -> nie animuj

	local _, sz = model:GetBoundingBox()
	local st = {
		model = model, prof = prof,
		range = combat.range, interval = 1 / math.max(combat.fireRate, 0.05),
		acc = math.random() * 0.4,
		baseCF = model:GetPivot(),
		scale = math.clamp(sz.Y / 5.5, 0.4, 1.2),
		reach = sz.Z * 0.5 + 0.4,
		chest = sz.Y * 0.12,
		recoilAmt = 0, recoilApplied = false,
	}
	setupFx(model, prof, st)
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
		task.spawn(function()
			bindFolder(Workspace:WaitForChild("WR_Units"))
		end)
	end
end

function UnitCombatAnimator._StateForTest()
	local n = 0
	for _ in pairs(_tracked) do n += 1 end
	return { tracked = n }
end

return UnitCombatAnimator
