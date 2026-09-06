--!nonstrict
-- ReplicatedStorage/Framework/AnimLab.luau
-- WARSZTAT ANIMACJI PROCEDURALNYCH (narzedzie agenta — sterowane kodem, bez GUI).
-- Prymitywy:
--   * joints(rig)            -> mapa nazwa->Motor6D (R6 i R15; generycznie po Motor6D w rigu)
--   * overlay(rig)           -> nakladka pozy NA animacje: BindToRenderStep PO priorytecie Character
--                               (Animator pisze Motor6D.Transform w kroku Character; my piszemy PO nim,
--                               wiec nasza poza WYGRYWA — fix "Animator zjada override" z 2026-09-06)
--   * armAimTransform(...)   -> DOKLADNY Transform barku, zeby ramie R6 CELOWALO w punkt swiata
--                               (jednostawowe IK policzone analitycznie; IKControl nie jest potrzebny dla R6,
--                               a z hum.EvaluateStateMachine=false bywa martwy — patrz RigAnimSetup)
--   * capture(rig)/buildSequence(...) -> zdejmij poze/pozy -> KeyframeSequence (do exportu jako Animation:
--                               zapisz do ServerStorage, MCP export_rbxm -> upload Open Cloud jako .rbxm)
-- KLIENT-only dla overlay (BindToRenderStep); reszta dziala wszedzie.
local RunService = game:GetService("RunService")

local AnimLab = {}

-- ── stawy ────────────────────────────────────────────────────────────────────────
-- generycznie: kazdy Motor6D w rigu, kluczem NAZWA motoru (R6: RootJoint/Neck/Shoulders/Hips; R15 analogicznie)
function AnimLab.joints(rig)
	local out = {}
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("Motor6D") then out[d.Name] = d end
	end
	return out
end

-- ── OVERLAY: poza na wierzchu animacji ──────────────────────────────────────────
-- Zwraca handle: { poses = {jointName->CFrame(Transform)}, weight=1, fn=function(dt, handle)?, stop() }.
-- Co klatke (PO Animatorze): opcjonalne handle.fn(dt, handle) (moze przeliczac pozy, np. celowanie),
-- potem kazdy joint z poses: Transform = Transform:Lerp(cel, weight). weight<1 = blend z animacja.
local _overlayId = 0
function AnimLab.overlay(rig)
	assert(RunService:IsClient(), "AnimLab.overlay: tylko klient (BindToRenderStep)")
	_overlayId += 1
	local bindName = "AnimLab_Overlay_" .. _overlayId
	local joints = AnimLab.joints(rig)
	local handle = { poses = {}, weight = 1 }
	RunService:BindToRenderStep(bindName, Enum.RenderPriority.Character.Value + 1, function(dt)
		if not rig.Parent then return end
		if handle.fn then handle.fn(dt, handle) end
		local w = math.clamp(handle.weight or 1, 0, 1)
		if w <= 0 then return end
		for name, cf in pairs(handle.poses) do
			local m = joints[name]
			if m and m.Parent then
				m.Transform = (w >= 1) and cf or m.Transform:Lerp(cf, w)
			end
		end
	end)
	function handle.stop()
		RunService:UnbindFromRenderStep(bindName)
	end
	return handle
end

-- ── rotBetween: minimalny obrot przeprowadzajacy wektor a w wektor b ───────────
-- (do celowania LUFA w cel: delta = rotBetween(lufaRef, kierunekDoCelu); armRot = delta * armRotRef)
function AnimLab.rotBetween(a, b)
	local axis = a:Cross(b)
	local d = math.clamp(a:Dot(b), -1, 1)
	if axis.Magnitude < 1e-5 then
		if d > 0 then return CFrame.new() end
		local orth = a:Cross(Vector3.yAxis)
		if orth.Magnitude < 1e-4 then orth = a:Cross(Vector3.xAxis) end
		return CFrame.fromAxisAngle(orth.Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(d))
end

-- ── ANALITYCZNE CELOWANIE RAMIENIA (R6, 1 staw) ────────────────────────────────
-- Zwraca Transform dla Motor6D barku taki, ze os ramienia (-Y czesci Arm) wskazuje z pivotu barku
-- na worldPos. Wzor Motor6D: Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()
-- -> Transform(rot) = rot(JW)^-1 * Rdes * rot(C1), obrot wokol pivotu (translacja 0) = staw nie rozjezdza sie.
-- side: "Right"|"Left". twistRef: opcjonalny wektor "przod" dla stabilnego skretu (domyslnie LookVector torsu).
function AnimLab.armAimTransform(rig, side, worldPos, twistRef)
	local joints = AnimLab.joints(rig)
	local m = joints[side .. " Shoulder"]
	if not m or not m.Part0 then return nil end
	local jw = m.Part0.CFrame * m.C0 -- world CFrame stawu
	local pivot = jw.Position
	local dir = worldPos - pivot
	if dir.Magnitude < 0.05 then return nil end
	dir = dir.Unit
	local yAxis = -dir -- os Y ramienia = przeciwna do kierunku (ramie "zwisa" po -Y)
	local ref = twistRef or m.Part0.CFrame.LookVector
	local zAxis = yAxis:Cross(ref)
	if zAxis.Magnitude < 0.05 then zAxis = yAxis:Cross(Vector3.yAxis) end
	zAxis = zAxis.Unit
	local xAxis = yAxis:Cross(zAxis).Unit
	local rDes = CFrame.fromMatrix(Vector3.zero, xAxis, yAxis, zAxis)
	return (jw.Rotation):Inverse() * rDes * m.C1.Rotation
end

-- ── CAPTURE -> KeyframeSequence ────────────────────────────────────────────────
-- capture(rig): zdejmij aktualna poze (Transform kazdego Motor6D; z animacja w locie = poza jak na ekranie).
function AnimLab.capture(rig)
	local out = {}
	for name, m in pairs(AnimLab.joints(rig)) do
		out[name] = m.Transform
	end
	return out
end

-- buildSequence(name, frames): frames = { {t=0, poses=capture(...)}, ... } -> KeyframeSequence.
-- Hierarchia Pose budowana generycznie z lancucha Part0->Part1 motorow (dziala R6 i R15).
-- Export: ks.Parent = ServerStorage -> MCP export_rbxm -> upload Open Cloud (Animation przyjmuje .rbxm).
function AnimLab.buildSequence(rig, name, frames, looped)
	local joints = AnimLab.joints(rig)
	-- rodzic kazdej czesci wg motorow: Part1.Name -> {motorName, Part0.Name}
	local parentOf, partByName = {}, {}
	local rootName = nil
	for mName, m in pairs(joints) do
		if m.Part0 and m.Part1 then
			parentOf[m.Part1.Name] = { motor = mName, parent = m.Part0.Name }
			partByName[m.Part1.Name], partByName[m.Part0.Name] = true, true
		end
	end
	for p in pairs(partByName) do
		if not parentOf[p] then rootName = p break end -- czesc bez motoru-rodzica = korzen (HRP)
	end
	local ks = Instance.new("KeyframeSequence")
	ks.Name = name
	ks.Loop = looped ~= false
	for _, fr in ipairs(frames) do
		local kf = Instance.new("Keyframe")
		kf.Time = fr.t or 0
		local poseByPart = {}
		local function ensurePose(partName)
			if poseByPart[partName] then return poseByPart[partName] end
			local pose = Instance.new("Pose")
			pose.Name = partName
			pose.Weight = 1
			local link = parentOf[partName]
			if link then
				pose.CFrame = fr.poses[link.motor] or CFrame.new()
				ensurePose(link.parent):AddSubPose(pose)
			else
				pose.CFrame = CFrame.new()
				pose.Parent = kf
			end
			poseByPart[partName] = pose
			return pose
		end
		for partName in pairs(partByName) do ensurePose(partName) end
		kf.Parent = ks
	end
	return ks
end

return AnimLab
