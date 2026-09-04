--!nonstrict
-- ReplicatedStorage/Framework/RigAnimSetup.luau
-- Przygotowuje model jednostki R6 do PRAWDZIWYCH animacji (Animator zamiast direct-CFrame):
--   * przyspawia luzne dodatki (Pistol/Uniform/Helmet...) do NAJBLIZSZEJ czesci rigu,
--     zeby jechaly z reka/tulowiem przy animacji (inaczej odczepia sie od statycznej pozy),
--   * kotwiczy TYLKO HumanoidRootPart, reszte odkotwicza (Motor6D moze napedzac Transform),
--   * wylacza maszyne stanow Humanoida (zero sil balansu/chodu) i zapewnia Animator.
-- Idempotentne. Zwraca Animator albo nil (gdy model to nie R6 humanoid).
local RigAnimSetup = {}

local CORE = {
	HumanoidRootPart = true, Torso = true, Head = true,
	["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
}

function RigAnimSetup.prepare(model)
	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	if not hum or hum.RigType ~= Enum.HumanoidRigType.R6 then return nil end
	local rig = hum.Parent
	local hrp = rig:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	-- czesci rdzenia rigu (cel spawow dla dodatkow)
	local coreParts = {}
	for _, d in ipairs(rig:GetChildren()) do
		if d:IsA("BasePart") and CORE[d.Name] then
			coreParts[#coreParts + 1] = d
		end
	end

	-- SPAW: luzne czesci -> rdzen. BRON (Rifle/RPG/Minigun...) to SZTYWNY prop rozciagniety przez cialo:
	-- welding KAZDEJ czesci do NAJBLIZSZEGO rdzenia OSOBNO rozrywa bron (czesc do reki, reszta do torsa) przy animacji.
	-- Fix: czesci tej samej PODMODELU-broni -> JEDEN rdzen (najblizszy srodkowi broni), sztywno. Uniform/dodatki rigu
	-- (przylegaja do konczyn) zostaja per-czesc do najblizszego rdzenia.
	local function nearestCore(pos)
		local best, bestD
		for _, c in ipairs(coreParts) do
			local dd = (c.Position - pos).Magnitude
			if not bestD or dd < bestD then bestD = dd; best = c end
		end
		return best
	end
	local function weldTo(d, core)
		if core and not d:FindFirstChild("RigAnimWeld") then
			local w = Instance.new("WeldConstraint")
			w.Name = "RigAnimWeld"; w.Part0 = d; w.Part1 = core; w.Parent = d
		end
	end
	local function topSub(part)
		local n = part
		while n and n.Parent ~= model do n = n.Parent end
		return n
	end
	local bySub = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not (CORE[d.Name] and d.Parent == rig) then
			local sub = topSub(d)
			bySub[sub] = bySub[sub] or {}
			table.insert(bySub[sub], d)
		end
	end
	for sub, parts in pairs(bySub) do
		local conforming = (sub == nil) or (sub == rig) or (sub.Name == "Uniform")
		if conforming then
			for _, d in ipairs(parts) do weldTo(d, nearestCore(d.Position)) end
		else
			local sum = Vector3.zero
			for _, d in ipairs(parts) do sum = sum + d.Position end
			local core = nearestCore(sum / #parts)
			for _, d in ipairs(parts) do weldTo(d, core) end
		end
	end

	-- KOTWICZENIE: tylko HRP zakotwiczony; reszta na spawach/Motorach (Animator moze ruszac)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = (d == hrp)
		end
	end
	hrp.Anchored = true

	-- Humanoid statyczny: bez maszyny stanow (zero sil balansu), bez auto-obrotu
	hum.AutoRotate = false
	pcall(function() hum.EvaluateStateMachine = false end)
	pcall(function() hum.RequiresNeck = false end)

	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	return animator
end

return RigAnimSetup
