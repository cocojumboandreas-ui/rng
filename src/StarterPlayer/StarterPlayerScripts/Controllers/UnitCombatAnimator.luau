--!nonstrict
-- StarterPlayerScripts/Controllers/UnitCombatAnimator.luau  (KLIENT — kosmetyka bojowa jednostek)
-- Prawdziwa walka/dmg = serwer (CombatService). Tu TYLKO wizual: postawione jednostki gracza
-- "strzelaja" do wrogow w zasiegu — muzzle flash + smuga (tracer) + lekki recoil, w rytmie fireRate.
-- Model-agnostic przez PROFILES[unitId]; SLICE = noob_soldier (pistolet), reszta dojdzie tym samym wzorcem.
--
-- Zrodla danych (bez nowych remote'ow): jednostki = Workspace.WR_Units (spawn serwera, atrybut UnitId/
-- OwnerUserId), wrogowie = pozycje z Workspace.WR_EnemyRender (widoczne Party = zywe na ekranie).
-- Animujemy TYLKO jednostki wlasnego gracza (LOD). Zasieg/fireRate z GameConfig (te same liczby co serwer).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local UnitCombatAnimator = {}

-- profile wizualne per typ (SLICE: noob_soldier). Kolory/rozmiary = "feel"; range/fireRate z configu.
local PROFILES = {
	noob_soldier = {
		flashColor = Color3.fromRGB(255, 225, 140),
		tracerColor = Color3.fromRGB(255, 220, 120),
		tracerWidth = 0.12,
		recoil = 0.18, -- study odrzutu
		flashTime = 0.05,
	},
}

local _tracked = {} -- model -> state
local _folder = nil -- WR_EnemyRender (cache)

-- ── wizual: reuzywalne czesci FX per jednostka ─────────────────────────────────
local function mkNeon(name, parent, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.Neon; p.Color = color
	p.Transparency = 1
	p.Parent = parent
	return p
end

local function setupFx(model, prof)
	local flash = mkNeon("WR_Muzzle", model, prof.flashColor)
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.7, 0.7, 0.7)
	local light = Instance.new("PointLight")
	light.Color = prof.flashColor; light.Range = 8; light.Brightness = 0; light.Parent = flash

	local tracer = mkNeon("WR_Tracer", model, prof.tracerColor)
	tracer.Size = Vector3.new(prof.tracerWidth, prof.tracerWidth, 1)
	return { flash = flash, light = light, tracer = tracer }
end

-- ── cele: najblizszy widoczny wrog w zasiegu (XZ) ──────────────────────────────
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
			if d2 <= bestD then
				bestD = d2; best = p.Position
			end
		end
	end
	return best
end

-- ── strzal (wizual) ────────────────────────────────────────────────────────────
local function muzzleCFrame(st)
	local pivot = st.model:GetPivot()
	local fwd = pivot.LookVector
	local pos = pivot.Position + fwd * (st.reach) + Vector3.new(0, st.chest, 0)
	return pos, fwd
end

local function fire(st, targetPos)
	local muzzle, fwd = muzzleCFrame(st)
	-- muzzle flash
	st.fx.flash.Position = muzzle
	st.fx.flash.Transparency = 0.1
	st.fx.light.Brightness = 3
	-- tracer: od muzzle do celu
	local dir = targetPos - muzzle
	local len = dir.Magnitude
	if len > 0.1 then
		st.fx.tracer.Size = Vector3.new(st.prof.tracerWidth, st.prof.tracerWidth, len)
		st.fx.tracer.CFrame = CFrame.lookAt(muzzle + dir * 0.5, targetPos)
		st.fx.tracer.Transparency = 0.15
	end
	st.flashUntil = os.clock() + st.prof.flashTime
	st.recoilAmt = st.prof.recoil * st.scale
end

-- ── petla ───────────────────────────────────────────────────────────────────────
local function step(dt)
	local now = os.clock()
	for model, st in pairs(_tracked) do
		if model.Parent then
			-- odrzut: dociagaj model z powrotem do bazy
			if st.recoilAmt > 0.005 then
				local fwd = st.baseCF.LookVector
				model:PivotTo(st.baseCF - fwd * st.recoilAmt)
				st.recoilAmt *= 0.72
			elseif st.recoilApplied then
				model:PivotTo(st.baseCF)
				st.recoilApplied = false
			end
			if st.recoilAmt > 0.005 then st.recoilApplied = true end

			-- wygas flash/tracer
			if st.flashUntil and now >= st.flashUntil then
				st.fx.flash.Transparency = 1
				st.fx.light.Brightness = 0
				st.fx.tracer.Transparency = 1
				st.flashUntil = nil
			end

			-- kadencja ognia
			st.acc += dt
			if st.acc >= st.interval then
				st.acc = 0
				local pivot = st.baseCF.Position
				local target = nearestEnemy(pivot.X, pivot.Z, st.range)
				if target then
					fire(st, target)
				end
			end
		end
	end
end

-- ── track/untrack ─────────────────────────────────────────────────────────────
local function track(model)
	if _tracked[model] then return end
	if model:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then return end
	local unitId = model:GetAttribute("UnitId")
	if not unitId then return end
	local prof = PROFILES[unitId]
	local combat = GameConfig.Units[unitId] and GameConfig.Units[unitId].combat
	if not prof or not combat then return end -- brak profilu/broni (np. blok) -> nie animuj

	local _, sz = model:GetBoundingBox()
	local st = {
		model = model, prof = prof,
		range = combat.range, interval = 1 / math.max(combat.fireRate, 0.05),
		acc = math.random() * 0.3, -- rozsynchronizuj salwy
		baseCF = model:GetPivot(),
		scale = math.clamp(sz.Y / 5.5, 0.4, 1.2), -- wzgledem oryginalnej wysokosci rig-a
		reach = sz.Z * 0.5 + 0.4,
		chest = sz.Y * 0.12,
		recoilAmt = 0, recoilApplied = false,
	}
	st.fx = setupFx(model, prof)
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
		if m:IsA("Model") then
			task.defer(track, m) -- poczekaj az serwer ustawi atrybuty/pozycje/pivot
		end
	end)
	units.ChildRemoved:Connect(untrack)
end

function UnitCombatAnimator.start()
	RunService.Heartbeat:Connect(step)
	-- WR_Units tworzy serwer przy pierwszym postawieniu (moze byc pozno) — czekaj bez blokowania
	local existing = Workspace:FindFirstChild("WR_Units")
	if existing then
		bindFolder(existing)
	else
		task.spawn(function()
			local units = Workspace:WaitForChild("WR_Units")
			bindFolder(units)
		end)
	end
end

-- Hook testowy: ile jednostek sledzonych.
function UnitCombatAnimator._StateForTest()
	local n = 0
	for _ in pairs(_tracked) do n += 1 end
	return { tracked = n }
end

return UnitCombatAnimator
