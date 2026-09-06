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

-- KANONICZNE R6 Motor6D C0/C1. Rigi z "Units Comission" maja WYPOZOWANE C0 (barki obrocone do trzymania
-- broni) -> animacje R6 (zakladaja domyslne C0) nakladaja sie i wychodza "rece zle / zly chod". Reset do
-- tych wartosci = CZYSTY R6 pod animacje. Robimy to PO zespawaniu munduru/broni (mundur trzyma sie ciala
-- przez WeldConstraint niezaleznie od pozy; bronie poprawiane osobno).
local R6_JOINTS = {
	RootJoint = { CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	Neck = { CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	["Right Shoulder"] = { CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	["Left Shoulder"] = { CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
	["Right Hip"] = { CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	["Left Hip"] = { CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
}

function RigAnimSetup.prepare(model)
	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	if not hum or hum.RigType ~= Enum.HumanoidRigType.R6 then return nil end
	local rig = hum.Parent
	local hrp = rig:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	-- czesci rdzenia rigu (cel spawow dla dodatkow). WAZNE: HRP jest KOTWICA (statyczna) -> NIE weldujemy do niej
	-- dodatkow (mundur/bron), bo nie szlyby za animacja torsu (Vest welded do HRP wygladalby "usuniety" gdy Motor6D
	-- animuje Torso -> goly tors wychodzi do przodu). Cel weldu = ANIMOWANE czesci ciala (Torso/Head/rece/nogi).
	local coreParts = {}
	for _, d in ipairs(rig:GetChildren()) do
		if d:IsA("BasePart") and CORE[d.Name] and d.Name ~= "HumanoidRootPart" then
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
	-- MUNDUR: weld po NAZWIE podmodelu (R_Arm->Right Arm itd.), NIE po pozycji. W pozie autorskiej rece
	-- byly przy klatce -> rekawy weldowaly sie do TORSU; po resecie stawow (czysty R6) rece odskakuja,
	-- a rekawy zostawaly przy klatce = "gole rece". Mapa nazw = deterministycznie na wlasciwa koncowke.
	local UNIFORM_MAP = {
		R_Arm = "Right Arm", L_Arm = "Left Arm", R_Leg = "Right Leg", L_Leg = "Left Leg",
		Torso = "Torso", Helmet = "Head", Head = "Head",
	}
	local function coreByName(nm)
		for _, c in ipairs(coreParts) do
			if c.Name == nm then return c end
		end
		return nil
	end
	for sub, parts in pairs(bySub) do
		local conforming = (sub == nil) or (sub == rig) or (sub.Name == "Uniform")
		if conforming then
			for _, d in ipairs(parts) do
				local core = nil
				if sub and sub.Name == "Uniform" then
					local n = d
					while n and n.Parent ~= sub do n = n.Parent end
					local mapped = n and UNIFORM_MAP[n.Name]
					if mapped then core = coreByName(mapped) end
				end
				weldTo(d, core or nearestCore(d.Position))
			end
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

	-- CZYSTY R6: zresetuj Motor6D C0/C1 do domyslnych R6 (rig ma wypozowane C0 -> psuje animacje).
	-- PO zespawaniu munduru (mundur trzyma sie ciala niezaleznie). Bronie poprawiane osobno.
	local function resetJoints()
		for _, d in ipairs(rig:GetChildren()) do
			if d:IsA("BasePart") then
				for _, mot in ipairs(d:GetChildren()) do
					if mot:IsA("Motor6D") and R6_JOINTS[mot.Name] then
						mot.C0 = R6_JOINTS[mot.Name][1]
						mot.C1 = R6_JOINTS[mot.Name][2]
					end
				end
			end
		end
	end
	resetJoints()
	-- GOTCHA (Heavy Trooper trzymal minigun w gore): parentowanie R6 do workspace ASYNCHRONICZNIE przywraca
	-- WYPOZOWANE Motor6D C0 (Humanoid odbudowuje jointy z oryginalu klona) -> reset sprzed parentowania znika
	-- (rewert osiada ~0.4s po parent). spawnModel/buildEnemyModel wolaja prepare PRZED parentowaniem, wiec
	-- powtarzamy reset przez kilka klatek PO parentowaniu, zeby wygrac wyscig z rewertem (reset po osiadnieciu TRZYMA).
	task.delay(0.1, function() if rig.Parent then resetJoints() end end)
	task.delay(0.35, function() if rig.Parent then resetJoints() end end)
	task.delay(0.7, function() if rig.Parent then resetJoints() end end)

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
