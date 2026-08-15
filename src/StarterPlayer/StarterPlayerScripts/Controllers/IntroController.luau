--!nonstrict
-- StarterPlayerScripts/Controllers/IntroController.luau (KLIENT, FAZA 1B — szkielet rytmu cutscenki intro)
-- Krok 2: izolowany tween bramy budynku dyktatora (cutscena.Bases.Base_2) + procedura marszu Kapitana.
-- Krok 3: system pomijania (CutsceneController.allowSkip) + hasSeenIntro (Net.GetIntroState/MarkIntroSeen).
-- Krok 4: PLACEHOLDER przejscia do normalnego startu gry — na czas cutscenki blokujemy sterowanie
-- gracza (PlayerModule:GetControls():Disable(), standardowy wzorzec Roblox dla cutscenek), odblokowujemy
-- w onDone (obejrzana LUB pominieta — tak czy inaczej "start gry"). Docelowa logika startu (fazy 2-5:
-- fade-in, spawn, itp.) podepnie sie w tym samym miejscu (miejsce oznaczone w onDone).
--
-- BRAMA: WLASNA kopia geometrii z BaseDoorService (worldAABB/leafParts/SLIDE_FRAC/OPEN_TIME/CLOSE_TIME),
-- ZERO wolania BaseDoorService/CollectionService(WR_EnemyBase)/PlotId — cutscena.WR_Nav.PathNode ma
-- PlotId=5 = kolizja z zywym placem gracza #5, wiec brama cutscenki jest CALKOWICIE odizolowana,
-- adresowana bezposrednio przez instancje (cutscena.Bases.Base_2), nigdy przez tag/plot lookup.
--
-- MARSZ KAPITANA: proceduralnie, wzorem EnemyRenderController (WALK_FREQ/LEG_AMP/BODY_BOB, ta sama
-- formula wymachu nog = bezposredni zapis CFrame na "Left Leg"/"Right Leg"), NIE prawdziwy AnimationTrack.
-- Kapitan (Workspace.Capitan) jest unanchored/Humanoid — na czas marszu KOTWICZYMY jego czesci (jak
-- zakotwiczone klony wrogow), zeby ruch byl deterministyczny; PRZYWRACAMY oryginalny stan dopiero gdy
-- cala cutscenka sie konczy/jest przerwana (nie gdy sam marsz dobiegnie konca — kamera moze jeszcze
-- trzymac kadr na Kapitanie milisekundy dluzej, teleport-powrot musi byc NIEWIDOCZNY dla gracza).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Controllers = script.Parent
local CutsceneController = require(Controllers:WaitForChild("CutsceneController"))
local NukeFxLib = require(Controllers:WaitForChild("NukeFxLib"))
local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

-- WaitForChild (nie FindFirstChild): jak w ConvoyController — Assets.Units moze jeszcze nie byc
-- zreplikowane do klienta w momencie require() (cold start, init.client leci przez ~40 kontrolerow).
local TANK_TMPL = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Units"):WaitForChild("Tank")

local IntroController = {}

-- ── brama: kopia stalych z BaseDoorService (IZOLOWANA — brak require tamtego modulu) ──
local SLIDE_FRAC = 0.95
local OPEN_TIME = 0.55
local CLOSE_TIME = 0.65
local DOOR_PREFIX = "Door"

-- ── marsz: te same stale co EnemyRenderController ──
local WALK_FREQ = 9
local LEG_AMP = 0.5
local BODY_BOB = 0.16
local MARCH_SPEED = 5.5 -- studs/s

local function worldAABB(model: Instance)
	local minv = Vector3.new(math.huge, math.huge, math.huge)
	local maxv = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local s = d.Size
			for _, sx in ipairs({ -0.5, 0.5 }) do
				for _, sy in ipairs({ -0.5, 0.5 }) do
					for _, sz in ipairs({ -0.5, 0.5 }) do
						local p = (d.CFrame * CFrame.new(s.X * sx, s.Y * sy, s.Z * sz)).Position
						minv = Vector3.new(math.min(minv.X, p.X), math.min(minv.Y, p.Y), math.min(minv.Z, p.Z))
						maxv = Vector3.new(math.max(maxv.X, p.X), math.max(maxv.Y, p.Y), math.max(maxv.Z, p.Z))
					end
				end
			end
		end
	end
	return (minv + maxv) * 0.5, (maxv - minv)
end

local function leafParts(model: Instance)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts[#parts + 1] = d
		end
	end
	return parts
end

-- ── stan bramy izolowanej (jeden gate, TYLKO cutscena.Bases.Base_2) ──
local _gate = nil -- {leaves={{part,closed,open},...}, state}
local _baseCenter = nil
local _gateCenter = nil
local _gateOutward = 1
local _gateSpawnCF = nil -- CFrame PRZED brama (na zewnatrz), skad startuje marsz, zwrocony na zewnatrz

-- ── cywile (mama + dzieci), Krok 1 Fazy 2: statyczna scenka "rozmowa przed domkami" ──
local CIVILIAN_NAMES = { "Mom", "Kid1", "Kid2" }
local _civilianHomeCF = {} -- model -> CFrame zastana w Workspace (poza "rozmowy" ustawiona w Studio)

-- ── domki wioski + czolgi (Krok 3 Fazy 2): rozwalka pod ostrzalem, rig ognia gaszony na starcie ──
local _houses = {} -- { {model, origPivot, fireParts={Part,...}, destroyed}, ... }
local _tanks = {} -- spawnione modele czolgow (sprzatane w restoreHouses)

local function buildCutsceneGate()
	local cutscena = Workspace:FindFirstChild("cutscena")
	local bases = cutscena and cutscena:FindFirstChild("Bases")
	local base = bases and bases:FindFirstChild("Base_2")
	if not base then
		warn("[IntroController] nie znaleziono cutscena.Bases.Base_2 — brama pominieta.")
		return
	end
	_baseCenter = select(1, worldAABB(base))
	local sides = { front = {}, back = {} }
	for _, ch in ipairs(base:GetChildren()) do
		if ch:IsA("Model") and ch.Name:sub(1, #DOOR_PREFIX) == DOOR_PREFIX then
			local c = select(1, worldAABB(ch))
			local sideKey = (c.Z >= _baseCenter.Z) and "front" or "back"
			table.insert(sides[sideKey], { model = ch, center = c })
		end
	end
	local leaves = (#sides.front >= 2) and sides.front or sides.back
	if #leaves < 2 then
		warn("[IntroController] Base_2: mniej niz 2 liscie bramy po jednej stronie — brama pominieta.")
		return
	end
	local sumX, sumZ, sumY = 0, 0, 0
	for _, lf in ipairs(leaves) do
		sumX += lf.center.X
		sumZ += lf.center.Z
		sumY += lf.center.Y
	end
	_gateCenter = Vector3.new(sumX / #leaves, sumY / #leaves, sumZ / #leaves)
	_gateOutward = (_gateCenter.Z >= _baseCenter.Z) and 1 or -1

	_gate = { leaves = {}, state = "closed" }
	for _, lf in ipairs(leaves) do
		local _, sz = worldAABB(lf.model)
		local dir = (lf.center.X < _gateCenter.X) and -1 or 1
		local slide = Vector3.new(dir * sz.X * SLIDE_FRAC, 0, 0)
		for _, part in ipairs(leafParts(lf.model)) do
			table.insert(_gate.leaves, { part = part, closed = part.Position, open = part.Position + slide })
		end
	end

	local aheadZ = _gateCenter.Z + _gateOutward * 6
	_gateSpawnCF = CFrame.lookAt(
		Vector3.new(_gateCenter.X, _gateCenter.Y, aheadZ),
		Vector3.new(_gateCenter.X, _gateCenter.Y, _gateCenter.Z + _gateOutward * 20)
	)
end

local function animateGate(opening: boolean)
	if not _gate then
		return
	end
	local target = opening and "open" or "closed"
	if _gate.state == target then
		return
	end
	_gate.state = target
	local info = TweenInfo.new(opening and OPEN_TIME or CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, lf in ipairs(_gate.leaves) do
		if lf.part and lf.part.Parent then
			TweenService:Create(lf.part, info, { Position = opening and lf.open or lf.closed }):Play()
		end
	end
end

-- Znajduje cywilow (Workspace root, jak Capitan/Flag) i zapamietuje ich zastana poze jako "dom"
-- (pozycja rozmowy sprzed domkow, ustawiona edycyjnie w Studio) — do przywrocenia w restoreCivilians().
local function buildCivilians()
	for _, nm in ipairs(CIVILIAN_NAMES) do
		local m = Workspace:FindFirstChild(nm)
		if m and not _civilianHomeCF[m] then
			_civilianHomeCF[m] = m:GetPivot()
		end
	end
end

-- Chowa cywilow tuz za bohaterem (heroCFrame), rozstawionych w linii, tweenem NumberValue (wzorzec
-- ConvoyController). Krok 3 Fazy 2: wolane NAPRAWDE z startTankAssault(), tuz przed wjazdem czolgow.
function IntroController.hideCiviliansBehindHero(heroCFrame: CFrame, duration: number?)
	duration = duration or 1.0
	local behindOffsets = { Vector3.new(-3, 0, 3), Vector3.new(0, 0, 3.6), Vector3.new(3, 0, 3) }
	local i = 0
	for _, nm in ipairs(CIVILIAN_NAMES) do
		local m = Workspace:FindFirstChild(nm)
		if m then
			i += 1
			local startCF = m:GetPivot()
			local targetCF = heroCFrame * CFrame.new(behindOffsets[i] or Vector3.new(0, 0, 3))
			local nv = Instance.new("NumberValue")
			nv.Value = 0
			nv.Changed:Connect(function(v)
				m:PivotTo(startCF:Lerp(targetCF, v))
			end)
			nv.Parent = m
			TweenService:Create(nv, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 }):Play()
			task.delay(duration + 0.1, function()
				nv:Destroy()
			end)
		end
	end
end

-- Pelny powrot cywilow do zastanej pozy "rozmowy" — wywolywane WYLACZNIE gdy cutscenka sie
-- konczy/jest przerwana (jak restoreCapitan), NIGDY w trakcie.
local function restoreCivilians()
	for m, homeCF in pairs(_civilianHomeCF) do
		if m.Parent then
			m:PivotTo(homeCF)
		end
	end
end

-- ── domki wioski (Krok 3 Fazy 2) ──
-- Kazda chatka siedzi we WLASNYM, identycznie nazwanym folderze "Model" pod cutscena.Nature (duplikaty
-- nazw sa normalne w tej scenie — adresujemy przez FindFirstChild("Simple wooden house") wewnatrz
-- kazdego folderu z osobna, NIGDY przez tag/PlotId). Rig ognia (8x Part "Fire" z PointLight/Smoke/
-- Particles/Sound) jest WLACZONY od razu przez artyste — Krok 1 pokazal domki plonace od 1. klatki
-- cutscenki; gasimy go tutaj RAZ na starcie jako jedyne realne zrodlo prawdy nad stanem ognia.
local function buildHouses()
	if #_houses > 0 then
		return
	end
	local cutscena = Workspace:FindFirstChild("cutscena")
	local nature = cutscena and cutscena:FindFirstChild("Nature")
	if not nature then
		return
	end
	for _, folder in ipairs(nature:GetChildren()) do
		if folder:IsA("Model") then
			local house = folder:FindFirstChild("Simple wooden house")
			if house then
				local fireParts = {}
				for _, c in ipairs(folder:GetChildren()) do
					if c.Name == "Fire" and c:IsA("BasePart") then
						table.insert(fireParts, c)
					end
				end
				for _, fp in ipairs(fireParts) do
					local light, smoke, particles, sound = fp:FindFirstChild("Light"), fp:FindFirstChild("Smoke"), fp:FindFirstChild("Particles"), fp:FindFirstChild("Sound")
					if light then light.Enabled = false end
					if smoke then smoke.Enabled = false end
					if particles then particles.Enabled = false end
					if sound then sound:Stop() end
				end
				table.insert(_houses, { model = house, origPivot = house:GetPivot(), fireParts = fireParts, destroyed = false })
			end
		end
	end
end

local function igniteFireRig(fireParts)
	for _, fp in ipairs(fireParts) do
		local light, smoke, particles, sound = fp:FindFirstChild("Light"), fp:FindFirstChild("Smoke"), fp:FindFirstChild("Particles"), fp:FindFirstChild("Sound")
		if light then light.Enabled = true end
		if smoke then smoke.Enabled = true end
		if particles then particles.Enabled = true end
		if sound then sound:Play() end
	end
end

local HOUSE_COLLAPSE_TIME = 1.3

-- Zawala chatke (przechyl + zapadniecie) i zapala jej rig ognia — wywolywane gdy czolg "trafia" dom.
local function destroyHouse(entry)
	if entry.destroyed then
		return
	end
	entry.destroyed = true
	igniteFireRig(entry.fireParts)
	local from = entry.model:GetPivot()
	local to = from * CFrame.Angles(0, 0, math.rad(33)) * CFrame.new(0, -2.2, 0)
	local nv = Instance.new("NumberValue")
	nv.Value = 0
	nv.Changed:Connect(function(v)
		if entry.model.Parent then
			entry.model:PivotTo(from:Lerp(to, v))
		end
	end)
	TweenService:Create(nv, TweenInfo.new(HOUSE_COLLAPSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 1 }):Play()
	task.delay(HOUSE_COLLAPSE_TIME + 0.1, function()
		nv:Destroy()
	end)
end

-- Pelny powrot obu chatek + sprzatniecie czolgow — jak restoreCapitan/restoreCivilians, wywolywane
-- WYLACZNIE gdy cala cutscenka sie konczy/jest przerwana, NIGDY w trakcie.
local function restoreHouses()
	for _, entry in ipairs(_houses) do
		if entry.model.Parent then
			entry.model:PivotTo(entry.origPivot)
		end
		for _, fp in ipairs(entry.fireParts) do
			local light, smoke, particles, sound = fp:FindFirstChild("Light"), fp:FindFirstChild("Smoke"), fp:FindFirstChild("Particles"), fp:FindFirstChild("Sound")
			if light then light.Enabled = false end
			if smoke then smoke.Enabled = false end
			if particles then particles.Enabled = false end
			if sound then sound:Stop() end
		end
		entry.destroyed = false
	end
	for _, tank in ipairs(_tanks) do
		if tank.Parent then
			tank:Destroy()
		end
	end
	_tanks = {}
end

-- ── czolgi (Krok 3 Fazy 2) — wzorzec ConvoyController (spawn -> wjazd -> ogien), uproszczony:
-- Tank to JEDEN sztywny model (bez osobnej wiezyczki/kierowcy jak Jeep), wiec bez mountGun/mountDriver.
local function tankWorldParent()
	return Workspace:FindFirstChild("WR_FxRoot") or Workspace
end

local function spawnTank(pos: Vector3, rot: CFrame)
	if not TANK_TMPL then
		return nil
	end
	local m = TANK_TMPL:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	m.Parent = tankWorldParent()
	m:PivotTo(CFrame.new(pos) * rot)
	table.insert(_tanks, m)
	return m
end

-- Blysk lufy + natychmiastowe zawalenie celu — czolg juz stoi w pozycji ostrzalu.
local function fireTankAndDestroy(tank, houseEntry)
	local muzzle = tank:FindFirstChild("Cannon") or tank.PrimaryPart or tank:FindFirstChildWhichIsA("BasePart")
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 200, 120)
	flash.Range = 24
	flash.Brightness = 6
	flash.Parent = muzzle
	task.delay(0.18, function()
		flash:Destroy()
	end)
	destroyHouse(houseEntry)
end

-- Wjazd 1 czolgu do pozycji ostrzalu przed dana chatka (NumberValue+Lerp, ten sam idiom co
-- hideCiviliansBehindHero — NIE CFrameValue+TweenService), potem ostrzal.
local function driveTankAndFire(spawnPos: Vector3, stopPos: Vector3, rot: CFrame, driveT: number, houseEntry)
	local tank = spawnTank(spawnPos, rot)
	if not tank then
		return
	end
	local nv = Instance.new("NumberValue")
	nv.Value = 0
	nv.Changed:Connect(function(v)
		if tank.Parent then
			tank:PivotTo(CFrame.new(spawnPos:Lerp(stopPos, v)) * rot)
		end
	end)
	local tw = TweenService:Create(nv, TweenInfo.new(driveT, Enum.EasingStyle.Linear), { Value = 1 })
	tw:Play()
	tw.Completed:Wait()
	nv:Destroy()
	fireTankAndDestroy(tank, houseEntry)
end

local TANK_DRIVE_TIME = 1.6
local TANK_STAGGER = 0.4

-- Ujecie ataku czolgow: kazdy z 2 czolgow wjezdza od strony przeciwnej do wioski i niszczy SWOJA
-- chatke. Cywile znikaja za Kapitanem TUZ PRZED wjazdem (prawdziwe wywolanie hideCiviliansBehindHero
-- z Kroku 1, celujac w aktualna pozycje Kapitana — koniec gestu "rozkaz ataku").
local function startTankAssault()
	buildHouses()
	if #_houses == 0 then
		warn("[IntroController] nie znaleziono chatek wioski — atak czolgow pominiety.")
		return
	end

	local capitan = Workspace:FindFirstChild("Capitan")
	local dummy = capitan and capitan:FindFirstChild("Dummy")
	if dummy then
		IntroController.hideCiviliansBehindHero(dummy:GetPivot(), 0.8)
	end

	for i, entry in ipairs(_houses) do
		local housePos = entry.origPivot.Position
		local spawnPos = housePos + Vector3.new(0, 0, 45)
		local stopPos = housePos + Vector3.new(0, 0, 14)
		local rot = CFrame.lookAt(Vector3.new(), housePos - stopPos)
		task.delay((i - 1) * TANK_STAGGER, function()
			driveTankAndFire(spawnPos, stopPos, rot, TANK_DRIVE_TIME, entry)
		end)
	end
end

-- ── marsz Kapitana (proceduralny, wzorem EnemyRenderController) ──
local function findExact(model, name)
	local ln = name:lower()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower() == ln then
			return d
		end
	end
	return nil
end

local _marchConn = nil
local _marchRestore = nil -- function() przywroc oryginalny stan Kapitana (pivot + Anchored)

-- Zatrzymuje SAM ruch (odlacza RenderStepped), Kapitan zostaje tam gdzie stoi — do wywolania gdy
-- marsz naturalnie dobiegnie konca (kamera moze jeszcze na nim trzymac kadr chwile dluzej).
local function stopMarchLoop()
	if _marchConn then
		_marchConn:Disconnect()
		_marchConn = nil
	end
end

-- Pelny powrot Kapitana do stanu SPRZED marszu (pivot + Anchored) — wywolywane WYLACZNIE gdy cala
-- cutscenka sie konczy/jest przerwana (onDone), NIGDY w trakcie — inaczej gracz zobaczylby teleport.
local function restoreCapitan()
	stopMarchLoop()
	if _marchRestore then
		local ok, err = pcall(_marchRestore)
		if not ok then
			warn("[IntroController] restore Kapitana padl: " .. tostring(err))
		end
		_marchRestore = nil
	end
end

-- ── gest "rozkaz ataku" (Krok 2 Fazy 2) — proceduralnie, ta sama technika co marsz: bezposredni
-- zapis CFrame na zakotwiczone czesci (Dummy["Right Arm"] + Cloth.R_Arm rekawa razem, zeby rekaw
-- podazal za uniesionym ramieniem — Cloth normalnie jedzie SZTYWNO jako cala bryla, wiec bez tego
-- rekaw zostalby w dole podczas gdy naga reka Dummy sie unosi).
local _gestureConn = nil
local _gestureRestore = nil

local function stopGestureLoop()
	if _gestureConn then
		_gestureConn:Disconnect()
		_gestureConn = nil
	end
end

local function restoreGesture()
	stopGestureLoop()
	if _gestureRestore then
		local ok, err = pcall(_gestureRestore)
		if not ok then
			warn("[IntroController] restore gestu Kapitana padl: " .. tostring(err))
		end
		_gestureRestore = nil
	end
end

-- Unosi prawe ramie Kapitana z opuszczonej pozy do wyciagnietej-do-przodu (rozkaz ataku), trzyma
-- do konca `duration`. Kapitan stoi juz w miejscu (koniec marszu) — animujemy tylko ramie+rekaw.
local function startAttackGesture(duration: number)
	local capitan = Workspace:FindFirstChild("Capitan")
	if not capitan then
		warn("[IntroController] nie znaleziono Workspace.Capitan — gest pominiety.")
		return
	end
	local dummy = capitan:FindFirstChild("Dummy")
	local cloth = capitan:FindFirstChild("Cloth")
	if not dummy then
		warn("[IntroController] Capitan.Dummy nie znaleziony — gest pominiety.")
		return
	end
	local arm = findExact(dummy, "Right Arm")
	local clothArm = cloth and cloth:FindFirstChild("R_Arm")
	if not arm then
		warn("[IntroController] Dummy['Right Arm'] nie znaleziony — gest pominiety.")
		return
	end

	local origArmCFrame, origArmAnchored = arm.CFrame, arm.Anchored
	local origClothArmCFrame = clothArm and clothArm.CFrame
	local origClothArmAnchored = clothArm and clothArm.Anchored
	arm.Anchored = true
	if clothArm then
		clothArm.Anchored = true
	end

	_gestureRestore = function()
		arm.CFrame = origArmCFrame
		arm.Anchored = origArmAnchored
		if clothArm then
			clothArm.CFrame = origClothArmCFrame
			clothArm.Anchored = origClothArmAnchored
		end
	end

	local pivot0 = dummy:GetPivot()
	local armOffset = pivot0:ToObjectSpace(arm.CFrame)
	local half = arm.Size.Y * 0.5
	local clothArmOffset = clothArm and pivot0:ToObjectSpace(clothArm.CFrame)
	local clothHalf = clothArm and clothArm.Size.Y * 0.5
	local RAISE_FRAC = 0.45 -- czesc czasu na uniesienie, reszta = trzymanie wyciagnietej pozy
	local RAISE_ANGLE = math.rad(100)

	local t0 = os.clock()
	_gestureConn = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(function()
			local elapsed = os.clock() - t0
			local t = math.clamp(elapsed / duration, 0, 1)
			local raise = math.clamp(t / RAISE_FRAC, 0, 1)
			local angle = raise * RAISE_ANGLE
			local pivotNow = dummy:GetPivot()
			arm.CFrame = pivotNow * armOffset * (CFrame.new(0, half, 0) * CFrame.Angles(-angle, 0, 0) * CFrame.new(0, -half, 0))
			if clothArm then
				clothArm.CFrame = pivotNow * (clothArmOffset :: CFrame) * (CFrame.new(0, clothHalf, 0) * CFrame.Angles(-angle, 0, 0) * CFrame.new(0, -clothHalf, 0))
			end
			if t >= 1 then
				stopGestureLoop()
			end
		end)
		if not ok then
			warn("[IntroController] blad w gescie Kapitana, przerywam: " .. tostring(err))
			stopGestureLoop()
		end
	end)
end

-- Startuje marsz Kapitana od _gateSpawnCF na zewnatrz, trwa `duration` s.
local function startMarch(duration: number)
	if not _gateSpawnCF then
		warn("[IntroController] brak _gateSpawnCF — marsz pominiety.")
		return
	end
	local capitan = Workspace:FindFirstChild("Capitan")
	if not capitan then
		warn("[IntroController] nie znaleziono Workspace.Capitan — marsz pominiety.")
		return
	end
	local dummy = capitan:FindFirstChild("Dummy")
	local cloth = capitan:FindFirstChild("Cloth")
	if not dummy then
		warn("[IntroController] Capitan.Dummy nie znaleziony — marsz pominiety.")
		return
	end

	-- zapamietaj oryginalny stan (pivot + Anchored kazdej czesci) do przywrocenia po cutscence
	local origDummyPivot = dummy:GetPivot()
	local origClothPivot = cloth and cloth:GetPivot()
	local origAnchored = {}
	for _, d in ipairs(capitan:GetDescendants()) do
		if d:IsA("BasePart") then
			origAnchored[d] = d.Anchored
			d.Anchored = true -- deterministyczny ruch na czas marszu (jak zakotwiczone klony wrogow)
		end
	end

	_marchRestore = function()
		dummy:PivotTo(origDummyPivot)
		if cloth and origClothPivot then
			cloth:PivotTo(origClothPivot)
		end
		for part, wasAnchored in pairs(origAnchored) do
			if part.Parent then
				part.Anchored = wasAnchored
			end
		end
	end

	-- ustaw Kapitana w pozycji startowej marszu, zanim wyliczymy offsety nog (spojne z formula EnemyRenderController)
	-- UWAGA: clothOffset MUSI byc wyliczony PRZED teleportem dummy do _gateSpawnCF, wzgledem oryginalnego
	-- (wspolnego) pivota — inaczej _gateSpawnCF:ToObjectSpace(cloth:GetPivot()) zlapie STARY, odlegly
	-- dystans miedzy "Cloth" a nowa brama i PivotTo nizej stanie sie de facto no-opem (Cloth zostaje w miejscu).
	local clothOffset = cloth and origDummyPivot:ToObjectSpace(cloth:GetPivot())
	dummy:PivotTo(_gateSpawnCF)
	if cloth then
		cloth:PivotTo(_gateSpawnCF * (clothOffset :: CFrame))
	end

	local pivot0 = dummy:GetPivot()
	local legs = {}
	for i, nm in ipairs({ "Left Leg", "Right Leg" }) do
		local p = findExact(dummy, nm)
		if p then
			legs[#legs + 1] = { part = p, cf = pivot0:ToObjectSpace(p.CFrame), half = p.Size.Y * 0.5, phase = (i == 1) and 0 or math.pi }
		end
	end

	local targetPos = _gateSpawnCF.Position + _gateSpawnCF.LookVector * (MARCH_SPEED * duration)
	local heading = _gateSpawnCF.Rotation
	local t0 = os.clock()

	_marchConn = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(function()
			local elapsed = os.clock() - t0
			local t = math.clamp(elapsed / duration, 0, 1)
			local pos = _gateSpawnCF.Position:Lerp(targetPos, t)
			local bob = math.abs(math.sin(elapsed * WALK_FREQ)) * BODY_BOB
			local newPivot = CFrame.new(pos.X, pos.Y + bob, pos.Z) * heading

			dummy:PivotTo(newPivot)
			if cloth then
				cloth:PivotTo(newPivot * (clothOffset :: CFrame))
			end
			for _, leg in ipairs(legs) do
				local s = math.sin(elapsed * WALK_FREQ + leg.phase) * LEG_AMP
				leg.part.CFrame = newPivot * leg.cf * (CFrame.new(0, leg.half, 0) * CFrame.Angles(s, 0, 0) * CFrame.new(0, -leg.half, 0))
			end

			if t >= 1 then
				stopMarchLoop()
			end
		end)
		if not ok then
			warn("[IntroController] blad w marszu Kapitana, przerywam: " .. tostring(err))
			stopMarchLoop()
		end
	end)
end

-- ── Krok 4: PLACEHOLDER przejscia do normalnego startu gry (blokada/odblokada sterowania) ──
local function setControlsEnabled(enabled: boolean)
	local ok, err = pcall(function()
		local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
		local PlayerModule = require(playerScripts:WaitForChild("PlayerModule"))
		local controls = PlayerModule:GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
	if not ok then
		warn("[IntroController] setControlsEnabled(" .. tostring(enabled) .. ") padl: " .. tostring(err))
	end
end

-- ── Krok 4 Fazy 2: kontratak bohatera — kostka, 2x zolnierz z plakietka gracza, ostrzal czolgow ──
local Debris = game:GetService("Debris")
local LocalPlayer = Players.LocalPlayer
local SOLDIER_TMPL = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Units"):WaitForChild("Soldier")

local _diceProp = nil
local _diceConn = nil
local _soldiers = {} -- spawnione modele Soldier (sprzatane w restoreHeroCounterattack)
-- Generacja: kazdy task.delay zapamietuje _heroGen z chwili startu; restoreHeroCounterattack() bije
-- licznik, wiec spoznione callbacki (skip zlapany MIEDZY dice-spin a spawnem/ogniem zolnierzy) widza
-- "stara" generacje i grzecznie sie wycofuja, zamiast wskrzeszac zolnierzy/kostke PO juz wykonanym sprzataniu.
local _heroGen = 0

local DICE_SPIN_TIME = 1.3
local SOLDIER_FLY_TIME = 0.9
local SOLDIER_FIRE_DELAY = 0.3

-- Pozycja/orientacja "bohatera": zywa postac gracza (jak IntroController.testHideCivilians), z fallbackiem
-- na plot PlayerBase_5 gdy postac jeszcze nie zespawnowana. Patrzy w strone srodka wioski (housesMid) —
-- DETERMINISTYCZNE kadrowanie niezalezne od tego, w ktora strone akurat stoi zywy gracz.
local function heroFacingCF(): CFrame
	local char = LocalPlayer and LocalPlayer.Character
	local pos
	if char then
		local ok, cf = pcall(function()
			return char:GetPivot()
		end)
		pos = ok and cf.Position or nil
	end
	if not pos then
		local plot = Workspace.cutscena and Workspace.cutscena.Plots:FindFirstChild("PlayerBase_5")
		pos = (plot and plot:GetPivot().Position) or Vector3.new(-787.5, 0.5, 142)
	end
	local housesMid, n = Vector3.new(), 0
	for _, entry in ipairs(_houses) do
		housesMid += entry.origPivot.Position
		n += 1
	end
	housesMid = (n > 0) and (housesMid / n) or (pos + Vector3.new(0, 0, 10))
	return CFrame.lookAt(pos, housesMid)
end

-- Minimalny prop kostki: biala kostka bez tekstur pipsow (w projekcie nie ma zadnego modelu 3D kostki —
-- system rolla jest UI-only), po prostu obraca sie w miejscu przed bohaterem przez DICE_SPIN_TIME.
local function buildDice(standCF: CFrame)
	if _diceProp then
		return
	end
	local d = Instance.new("Part")
	d.Name = "WR_HeroDice"
	d.Size = Vector3.new(1.3, 1.3, 1.3)
	d.Material = Enum.Material.SmoothPlastic
	d.Color = Color3.fromRGB(245, 245, 245)
	d.Anchored = true
	d.CanCollide = false
	d.CanQuery = false
	d.CanTouch = false
	d.CastShadow = false
	d.Parent = tankWorldParent()
	local basePos = standCF.Position + standCF.LookVector * 3 + Vector3.new(0, 3, 0)
	d:PivotTo(CFrame.new(basePos))
	_diceProp = d
	local t0 = os.clock()
	_diceConn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > DICE_SPIN_TIME then
			if _diceConn then
				_diceConn:Disconnect()
				_diceConn = nil
			end
			return
		end
		d:PivotTo(CFrame.new(basePos) * CFrame.Angles(t * 9, t * 6.5, t * 4))
	end)
end

-- Plakietka SurfaceGui+ImageLabel z avatarem GRACZA na glowie zolnierza — 1:1 wzorzec
-- LeaderboardService.resolveThumb (Players:GetUserThumbnailAsync, HeadShot 150x150), NIE Decal na mundurze.
local function attachHeroPlaque(model: Model)
	local dummy = model:FindFirstChild("Dummy")
	local head = dummy and dummy:FindFirstChild("Head")
	if not head or not LocalPlayer then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "WR_HeroPlaque"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.PixelsPerStud = 50
	gui.Parent = head
	local img = Instance.new("ImageLabel")
	img.Name = "PlayerImage"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = gui
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and content ~= "" then
		img.Image = content
	end
end

-- Wylatuje 1 zolnierz z boku bohatera do pozycji ostrzalu (NumberValue+Lerp, ten sam idiom co gdzie indziej
-- w tym pliku), zwraca model + koncowa pozycja (do wycelowania ognia).
local function spawnHeroSoldier(standCF: CFrame, sideOffset: number): (Model?, Vector3?)
	local m = SOLDIER_TMPL:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	m.Parent = tankWorldParent()
	local startPos = standCF.Position + Vector3.new(0, 9, 0) + standCF.RightVector * sideOffset
	local endPos = standCF.Position + standCF.LookVector * 5 + standCF.RightVector * sideOffset
	local rot = standCF.Rotation
	m:PivotTo(CFrame.new(startPos) * rot)
	attachHeroPlaque(m)
	table.insert(_soldiers, m)
	local nv = Instance.new("NumberValue")
	nv.Value = 0
	nv.Changed:Connect(function(v)
		if m.Parent then
			m:PivotTo(CFrame.new(startPos:Lerp(endPos, v)) * rot)
		end
	end)
	local tw = TweenService:Create(nv, TweenInfo.new(SOLDIER_FLY_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 })
	tw:Play()
	tw.Completed:Connect(function()
		nv:Destroy()
	end)
	return m, endPos
end

-- Blysk lufy + smuga (profil "soldier" z UnitCombatAnimator: flash 255,220,130 / tracer 255,210,90) —
-- sam FX, bez atrybutow WR_Units/celowania automatycznego (kadr jest wyrezyserowany, nie zywa walka).
local function soldierMuzzleFx(fromPos: Vector3, toPos: Vector3)
	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 220, 130)
	flash.Size = Vector3.new(0.6, 0.6, 0.6)
	flash.CFrame = CFrame.new(fromPos)
	flash.Parent = tankWorldParent()
	local light = Instance.new("PointLight")
	light.Color = flash.Color
	light.Range = 16
	light.Brightness = 5
	light.Parent = flash

	local dist = (toPos - fromPos).Magnitude
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 210, 90)
	tracer.Size = Vector3.new(0.14, 0.14, dist)
	tracer.CFrame = CFrame.lookAt(fromPos, toPos) * CFrame.new(0, 0, -dist / 2)
	tracer.Parent = tankWorldParent()

	Debris:AddItem(flash, 0.12)
	Debris:AddItem(tracer, 0.12)
end

-- Wybuch czolgu (wzorzec profilu "tank" z UnitCombatAnimator.boom — kula Neon rosnie+gasnie + PointLight) —
-- SAM FX, bez logiki bojowej/serwerowej; czolg jest juz tylko rekwizytem tej cutscenki (Krok 3).
local function tankBoomFx(pos: Vector3)
	local ball = Instance.new("Part")
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 150, 50)
	ball.Transparency = 0.1
	ball.Size = Vector3.new(1, 1, 1)
	ball.CFrame = CFrame.new(pos)
	ball.Parent = tankWorldParent()
	local light = Instance.new("PointLight")
	light.Color = ball.Color
	light.Range = 30
	light.Brightness = 8
	light.Parent = ball
	local nv = Instance.new("NumberValue")
	nv.Value = 0
	nv.Changed:Connect(function(v)
		if ball.Parent then
			ball.Size = Vector3.one * (1 + v * 16)
			ball.Transparency = 0.1 + v * 0.9
			light.Brightness = 8 * (1 - v)
		end
	end)
	TweenService:Create(nv, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 }):Play()
	task.delay(0.6, function()
		nv:Destroy()
		if ball.Parent then
			ball:Destroy()
		end
	end)
end

local function destroyTank(tank: Model)
	if not tank.Parent then
		return
	end
	tankBoomFx(tank:GetPivot().Position)
	tank:Destroy()
end

-- Ujecie kontrataku: kostka -> 2x zolnierz wylatuje -> ostrzal -> czolgi (z Kroku 3, wciaz zaparkowane
-- pod wioska) wybuchaja. Jesli nie ma czolgow (np. wywolane osobno w tescie) — bezpieczny early-return.
local function startHeroCounterattack()
	_heroGen += 1
	local myGen = _heroGen
	local standCF = heroFacingCF()
	buildDice(standCF)
	task.delay(DICE_SPIN_TIME * 0.6, function()
		if myGen ~= _heroGen then
			return
		end
		local soldierA, posA = spawnHeroSoldier(standCF, -3.5)
		local soldierB, posB = spawnHeroSoldier(standCF, 3.5)
		if not (soldierA or soldierB) then
			return
		end
		task.delay(SOLDIER_FLY_TIME + 0.1, function()
			if myGen ~= _heroGen then
				return
			end
			if #_tanks == 0 then
				warn("[IntroController] brak czolgow do ostrzelania — kontratak bohatera bez celu.")
				return
			end
			for i, tank in ipairs(_tanks) do
				if tank.Parent then
					local tpos = tank:GetPivot().Position
					local spos = ((i % 2 == 1) and posA or posB) or standCF.Position
					soldierMuzzleFx(spos + Vector3.new(0, 3, 0), tpos)
					task.delay(SOLDIER_FIRE_DELAY, function()
						if myGen ~= _heroGen then
							return
						end
						destroyTank(tank)
					end)
				end
			end
		end)
	end)
end

-- Pelne sprzatniecie: kostka + jej petla obrotu + obaj zolnierze (Destroy modelu kasuje tez plakietke-dziecko
-- glowy). Wywolywane WYLACZNIE z onDone, jak restoreHouses/restoreCivilians.
local function restoreHeroCounterattack()
	_heroGen += 1
	if _diceConn then
		_diceConn:Disconnect()
		_diceConn = nil
	end
	if _diceProp then
		if _diceProp.Parent then
			_diceProp:Destroy()
		end
		_diceProp = nil
	end
	for _, s in ipairs(_soldiers) do
		if s.Parent then
			s:Destroy()
		end
	end
	_soldiers = {}
end

-- ── Krok 5 finał: guzik -> atomowka -> biala biel -> serwerowy teleport na realny plac ──
-- Flash to CALKOWICIE ODDZIELNY, niezaleznie zarzadzany ScreenGui (WLASNY DisplayOrder, NAD
-- WR_CutsceneFx=480 i WR_AtomicFx=500) — musi zamaskowac KAZDY stan kamery/UI pod spodem,
-- niezaleznie od tego kiedy/jak CutsceneController.teardown() zrobi swoje (wlasny zegar shot-listy,
-- nie czekamy na niego i go nie przerywamy). Biel gasnie WYLACZNIE po potwierdzonym IntroTeleportHomeDone
-- (lub po FINALE_SAFETY_TIMEOUT, gdyby sygnal serwera zgubil sie w sieci) — nigdy po sztywnym timerze klienta.
local BUTTON_GESTURE_TIME = 1.4
local NUKE_SHOT_DURATION = 3.6
local FLASH_IN_TIME = 0.18
local FLASH_OUT_TIME = 0.4
local FINALE_SAFETY_TIMEOUT = 5.0

local _finaleGen = 0
local _finalePending = false -- true od startFinale() do potwierdzonego powrotu -> onDone NIE odblokuje sterowania wczesniej
local _finaleDoneConn = nil
local _finaleFlashGui = nil
local _capitanStandPos = nil -- ustawiane w buildShots() (pozycja Kapitana po marszu) — tez punkt relokacji bohatera

local function ensureFinaleFlashGui()
	if _finaleFlashGui and _finaleFlashGui.Parent then
		return _finaleFlashGui
	end
	local pg = LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_IntroFinaleFlash"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 600
	gui.Parent = pg
	local frame = Instance.new("Frame")
	frame.Name = "Flash"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	_finaleFlashGui = gui
	return gui
end

local function resetFinaleState()
	_finaleGen += 1
	_finalePending = false
	if _finaleDoneConn then
		_finaleDoneConn:Disconnect()
		_finaleDoneConn = nil
	end
	if _finaleFlashGui and _finaleFlashGui.Parent then
		local frame = _finaleFlashGui:FindFirstChild("Flash")
		if frame then
			frame.BackgroundTransparency = 1
		end
		_finaleFlashGui.Enabled = false
	end
end

local function beginFlashHold()
	local gui = ensureFinaleFlashGui()
	gui.Enabled = true
	local frame = gui:FindFirstChild("Flash")
	if frame then
		TweenService:Create(frame, TweenInfo.new(FLASH_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0 }):Play()
	end
end

local function endFlashHold()
	if not (_finaleFlashGui and _finaleFlashGui.Parent) then
		return
	end
	local gui = _finaleFlashGui
	local frame = gui:FindFirstChild("Flash")
	if not frame then
		gui.Enabled = false
		return
	end
	local tw = TweenService:Create(frame, TweenInfo.new(FLASH_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
	tw:Play()
	tw.Completed:Connect(function()
		if gui.Parent then
			gui.Enabled = false
		end
	end)
end

-- Kosmetyczna relokacja PRAWDZIWEJ postaci gracza w diarome finalu — offekranowo (kamera
-- CutsceneController patrzy na wybuch, nie na bohatera), zeby nastepujacy serwerowy PivotTo
-- na realny plac byl PRAWDZIWYM przeskokiem (Opcja B), nie no-opem.
local function relocateHeroIntoDiorama()
	local char = LocalPlayer and LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not hrp then
		return
	end
	local pos = _capitanStandPos or (_gateSpawnCF and _gateSpawnCF.Position) or hrp.Position
	local lookAt = _baseCenter or (pos + Vector3.new(0, 0, 10))
	local ok, err = pcall(function()
		char:PivotTo(CFrame.lookAt(pos + Vector3.new(6, 0, 6), lookAt))
	end)
	if not ok then
		warn("[IntroController] relocateHeroIntoDiorama padl: " .. tostring(err))
	end
end

-- Guzik nacisniety -> atomowka (NukeFxLib, BEZ logiki czyszczenia fali serwera) -> trzymaj biel ->
-- popros serwer o powrot na realny plac -> gasnij DOPIERO po jego potwierdzeniu. Serwer odmierza
-- WLASNY zegar (IntroService.TELEPORT_T, wzorzec AtomicStrikeService) — klient nigdy nie zgaduje.
local function startFinale()
	_finaleGen += 1
	local myGen = _finaleGen
	_finalePending = true

	local impactPos = (Workspace:FindFirstChild("Nuke_Warhead") and Workspace.Nuke_Warhead.Position) or _capitanStandPos or _baseCenter or Vector3.new()
	local ok1, err1 = pcall(NukeFxLib.bigMushroom, impactPos)
	if not ok1 then
		warn("[IntroController] NukeFxLib.bigMushroom padl: " .. tostring(err1))
	end

	relocateHeroIntoDiorama()
	beginFlashHold()

	local ok2, err2 = pcall(function()
		Net.get("IntroTeleportHome"):FireServer()
	end)
	if not ok2 then
		warn("[IntroController] IntroTeleportHome FireServer padl: " .. tostring(err2))
	end

	if _finaleDoneConn then
		_finaleDoneConn:Disconnect()
		_finaleDoneConn = nil
	end
	_finaleDoneConn = Net.get("IntroTeleportHomeDone").OnClientEvent:Connect(function()
		if myGen ~= _finaleGen then
			return
		end
		if _finaleDoneConn then
			_finaleDoneConn:Disconnect()
			_finaleDoneConn = nil
		end
		_finalePending = false
		endFlashHold()
		setControlsEnabled(true)
		print("[IntroController] finał: teleport na realny plac potwierdzony przez serwer.")
	end)

	task.delay(FINALE_SAFETY_TIMEOUT, function()
		if myGen ~= _finaleGen or not _finalePending then
			return
		end
		warn("[IntroController] finał: brak IntroTeleportHomeDone po " .. FINALE_SAFETY_TIMEOUT .. "s — awaryjne odblokowanie.")
		if _finaleDoneConn then
			_finaleDoneConn:Disconnect()
			_finaleDoneConn = nil
		end
		_finalePending = false
		endFlashHold()
		setControlsEnabled(true)
	end)
end

-- Odblokowanie sterowania po zakonczeniu cutscenki (normalne LUB skip). Gdy finał jest w toku
-- (_finalePending) — NIC nie robimy tutaj: startFinale()'s wlasny lancuch (IntroTeleportHomeDone
-- LUB FINALE_SAFETY_TIMEOUT) i tak odblokuje sterowanie, gdy przyjdzie jego czas — CutsceneController
-- juz zrobil swoj teardown (bary/kamera/UI), ale flash (osobny, wyzszy DisplayOrder) wciaz to maskuje.
local function finalizeControlsAfterCutscene(wasCancelled: boolean)
	if _finalePending then
		print("[IntroController] play zakonczony (cancelled=" .. tostring(wasCancelled) .. "), finał w toku — sterowanie wroci po potwierdzonym teleporcie.")
		return
	end
	setControlsEnabled(true)
	print("[IntroController] play zakonczony, cancelled=" .. tostring(wasCancelled) .. " — normalny start gry.")
end

-- ── shot-lista (Krok 5 Fazy 2: +2 ujecia finalu — guzik + atomowka/biel — DOKLADANE ZAWSZE, poza blokiem #_houses) ──
local function buildShots()
	if not _baseCenter or not _gateCenter or not _gateSpawnCF then
		return nil
	end
	local wide = CFrame.lookAt(_baseCenter + Vector3.new(0, 45, -_gateOutward * 70), _baseCenter)
	local gateShot = CFrame.lookAt(_gateCenter + Vector3.new(18, 8, _gateOutward * 14), _gateCenter)
	local marchTarget = _gateSpawnCF.Position + _gateSpawnCF.LookVector * (MARCH_SPEED * 3.5)
	_capitanStandPos = marchTarget
	local marchShot = CFrame.lookAt(marchTarget + Vector3.new(14, 6, 0), marchTarget)
	local gestureFocus = marchTarget + Vector3.new(0, 3, 0)
	local gestureShot = CFrame.lookAt(marchTarget + Vector3.new(9, 5, 5), gestureFocus)
	local shots = {
		{ cf = wide, duration = 2.2 },
		{ cf = gateShot, duration = 1.8 },
		{ cf = marchShot, duration = 3.5 },
		{ cf = gestureShot, duration = 2.0 },
	}
	if #_houses > 0 then
		local sumPos = Vector3.new()
		for _, entry in ipairs(_houses) do
			sumPos += entry.origPivot.Position
		end
		local housesMid = sumPos / #_houses
		local assaultShot = CFrame.lookAt(housesMid + Vector3.new(75, 22, 5), housesMid + Vector3.new(0, 3, 15))
		table.insert(shots, { cf = assaultShot, duration = 4.2 })

		local heroCF = heroFacingCF()
		local heroShot = CFrame.lookAt(heroCF.Position + Vector3.new(-10, 7, -14), heroCF.Position + heroCF.LookVector * 12)
		table.insert(shots, { cf = heroShot, duration = 3.4 })
	end

	-- Krok 5 finał — ZAWSZE dokladane (niezaleznie od #_houses), kind-tagged zeby onShotStart
	-- rozpoznawal je PRZED numerycznymi idx (pozycja w tablicy plynie w zaleznosci od #_houses).
	local buttonFocus = _capitanStandPos or _gateSpawnCF.Position or _baseCenter
	local buttonShot = CFrame.lookAt(buttonFocus + Vector3.new(4, 4, 4), buttonFocus + Vector3.new(0, 2, 0))
	table.insert(shots, { cf = buttonShot, duration = 2.0, kind = "button" })
	local nukeTargetPos = (Workspace:FindFirstChild("Nuke_Warhead") and Workspace.Nuke_Warhead.Position) or buttonFocus
	local nukeShot = CFrame.lookAt(nukeTargetPos + Vector3.new(-40, 30, -40), nukeTargetPos)
	table.insert(shots, { cf = nukeShot, duration = NUKE_SHOT_DURATION, kind = "nuke" })

	return shots
end

-- Odpala cutscenke. opts.allowSkip(boolean) — patrz CutsceneController.play. Zawsze, niezaleznie od
-- wyniku (dokonczona/pominieta), zglasza serwerowi Net.MarkIntroSeen -> hasSeenIntro=true w profilu.
function IntroController.play(opts: any?)
	opts = opts or {}
	resetFinaleState()
	buildCutsceneGate()
	buildCivilians()
	buildHouses()
	local shots = buildShots()
	if not shots then
		warn("[IntroController] nie udalo sie zbudowac shot-listy — cutscenka pominieta.")
		return false
	end
	setControlsEnabled(false)
	local started = CutsceneController.play(shots, {
		allowSkip = opts.allowSkip == true,
		onShotStart = function(idx, shot)
			if shot.kind == "button" then
				startAttackGesture(BUTTON_GESTURE_TIME)
			elseif shot.kind == "nuke" then
				startFinale()
			elseif idx == 2 then
				animateGate(true)
			elseif idx == 3 then
				startMarch(3.5)
			elseif idx == 4 then
				startAttackGesture(2.0)
			elseif idx == 5 then
				startTankAssault()
			elseif idx == 6 then
				startHeroCounterattack()
			end
		end,
		onDone = function(wasCancelled)
			-- KOLEJNOSC WAZNA: gest (warstwa wewnetrzna, nadpisuje CFrame konkretnych czesci) musi
			-- sie cofnac PRZED marszem (warstwa zewnetrzna, PivotTo calego modelu) — inaczej marchRestore
			-- przywraca ramie+rekaw na miejsce, a nastepujacy PO nim restoreGesture ponownie nadpisuje
			-- je STARYM zrzutem CFrame sprzed marszu-cofniecia (dlon zostawala przy bramie zamiast wrocic).
			restoreGesture()
			restoreCapitan()
			restoreHouses()
			restoreHeroCounterattack()
			restoreCivilians()
			animateGate(false)
			local ok, err = pcall(function()
				Net.get("MarkIntroSeen"):FireServer()
			end)
			if not ok then
				warn("[IntroController] MarkIntroSeen padl: " .. tostring(err))
			end
			-- PLACEHOLDER: tu wpina sie docelowy start gry (fazy 3-5, po intro). Odblokowanie
			-- sterowania jest WARUNKOWE — patrz finalizeControlsAfterCutscene (finał Kroku 5).
			finalizeControlsAfterCutscene(wasCancelled)
		end,
	})
	if not started then
		setControlsEnabled(true) -- CutsceneController.play() odrzucil start (np. juz aktywna) — nie zostaw zablokowanego gracza
	end
	return started
end

-- Test manualny (skip zawsze dostepny, zeby QA nie utknelo w petli) — wolane recznie ze Studio.
function IntroController.testPlay()
	return IntroController.play({ allowSkip = true })
end

-- Test manualny Kroku 1 Fazy 2 — buduje cywilow (jesli jeszcze nie) i recznie wywoluje PLACEHOLDER
-- chowania sie za bohaterem, celujac w aktualna pozycje postaci gracza (lub PlayerBase_5 jesli brak).
function IntroController.testHideCivilians()
	buildCivilians()
	local heroCF
	local char = Players.LocalPlayer and Players.LocalPlayer.Character
	if char then
		heroCF = char:GetPivot()
	else
		local plot = Workspace.cutscena and Workspace.cutscena.Plots:FindFirstChild("PlayerBase_5")
		heroCF = plot and plot:GetPivot() or CFrame.new(-787.5, 0.5, 142)
	end
	IntroController.hideCiviliansBehindHero(heroCF)
	return true
end

-- Test manualny gestu Kapitana (Krok 2 Fazy 2) — trzyma podniesiona reke przez `hold` sekund,
-- POZA pelna sekwencja ujec, zeby dalo sie zlapac zrzut ekranu bez wyscigu z timerem shot-listy.
function IntroController.testGesture(hold: number?)
	startAttackGesture(hold or 4.0)
	return true
end

-- Kontroler: odpala sie przy wejsciu gracza (wpiety w init.client.luau ORDER). Pyta serwer o
-- hasSeenIntro i gra cutscenke z pomijaniem dostepnym TYLKO gdy gracz juz ja kiedys widzial/pominal.
-- Zapytanie serwera odbywa sie w task.spawn, zeby NIE blokowac reszty petli startu kontrolerow.
-- BRAMKA manualna (na zyczenie ownera): auto-trigger NIE gra cutscenki nikomu, dopoki ktos recznie
-- nie ustawi Workspace:SetAttribute("WR_IntroEnabled", true) w Studio. Domyslnie brak/false = wylaczone.
-- testPlay() (QA) NIE przechodzi przez ta bramke — dziala zawsze, niezaleznie od atrybutu.
function IntroController.start()
	task.spawn(function()
		if Workspace:GetAttribute("WR_IntroEnabled") ~= true then
			print("[IntroController] auto-start wylaczony (Workspace attribute WR_IntroEnabled != true) — uzyj testPlay() do QA.")
			return
		end
		local ok, state = pcall(function()
			return Net.get("GetIntroState"):InvokeServer()
		end)
		local hasSeenIntro = ok and type(state) == "table" and state.hasSeenIntro == true
		IntroController.play({ allowSkip = hasSeenIntro })
	end)
end

return IntroController
