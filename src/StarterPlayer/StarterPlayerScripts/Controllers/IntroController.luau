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
local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

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
	dummy:PivotTo(_gateSpawnCF)
	local clothOffset = cloth and _gateSpawnCF:ToObjectSpace(cloth:GetPivot())
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

-- ── shot-lista testowa Kroku 2 (3 ujecia: szeroko na baze -> brama -> Kapitan w marszu) ──
local function buildShots()
	if not _baseCenter or not _gateCenter or not _gateSpawnCF then
		return nil
	end
	local wide = CFrame.lookAt(_baseCenter + Vector3.new(0, 45, -_gateOutward * 70), _baseCenter)
	local gateShot = CFrame.lookAt(_gateCenter + Vector3.new(18, 8, _gateOutward * 14), _gateCenter)
	local marchTarget = _gateSpawnCF.Position + _gateSpawnCF.LookVector * (MARCH_SPEED * 3.5)
	local marchShot = CFrame.lookAt(marchTarget + Vector3.new(14, 6, 0), marchTarget)
	return {
		{ cf = wide, duration = 2.2 },
		{ cf = gateShot, duration = 1.8 },
		{ cf = marchShot, duration = 3.5 },
	}
end

-- Odpala cutscenke. opts.allowSkip(boolean) — patrz CutsceneController.play. Zawsze, niezaleznie od
-- wyniku (dokonczona/pominieta), zglasza serwerowi Net.MarkIntroSeen -> hasSeenIntro=true w profilu.
function IntroController.play(opts: any?)
	opts = opts or {}
	buildCutsceneGate()
	local shots = buildShots()
	if not shots then
		warn("[IntroController] nie udalo sie zbudowac shot-listy — cutscenka pominieta.")
		return false
	end
	setControlsEnabled(false)
	local started = CutsceneController.play(shots, {
		allowSkip = opts.allowSkip == true,
		onShotStart = function(idx, _shot)
			if idx == 2 then
				animateGate(true)
			elseif idx == 3 then
				startMarch(3.5)
			end
		end,
		onDone = function(wasCancelled)
			restoreCapitan()
			animateGate(false)
			local ok, err = pcall(function()
				Net.get("MarkIntroSeen"):FireServer()
			end)
			if not ok then
				warn("[IntroController] MarkIntroSeen padl: " .. tostring(err))
			end
			-- PLACEHOLDER: tu wpina sie docelowy start gry (fazy 2-5). Na razie: odblokuj sterowanie.
			setControlsEnabled(true)
			print("[IntroController] play zakonczony, cancelled=" .. tostring(wasCancelled) .. " — normalny start gry.")
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

-- Kontroler: odpala sie przy wejsciu gracza (wpiety w init.client.luau ORDER). Pyta serwer o
-- hasSeenIntro i gra cutscenke z pomijaniem dostepnym TYLKO gdy gracz juz ja kiedys widzial/pominal.
-- Zapytanie serwera odbywa sie w task.spawn, zeby NIE blokowac reszty petli startu kontrolerow.
function IntroController.start()
	task.spawn(function()
		local ok, state = pcall(function()
			return Net.get("GetIntroState"):InvokeServer()
		end)
		local hasSeenIntro = ok and type(state) == "table" and state.hasSeenIntro == true
		IntroController.play({ allowSkip = hasSeenIntro })
	end)
end

return IntroController
