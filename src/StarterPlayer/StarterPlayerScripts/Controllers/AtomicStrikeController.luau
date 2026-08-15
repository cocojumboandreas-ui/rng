--!nonstrict
-- StarterPlayerScripts/Controllers/AtomicStrikeController.luau  (KLIENT — TYLKO u gracza ktory odpalil)
-- Ultimate ATOMOWKA: pelna cutscenka po Net.AtomicStrikeCue. Serwer NIE czeka na zaden sygnal stad —
-- czysci fale wg WLASNEGO zegara (AtomicStrikeService.IMPACT_T). TU tylko oprawa: bary, kamera Scriptable,
-- rakieta spada, twarde ciecie na kadr bazy, blysk w klatce uderzenia, grzyb+shockwave na calej mapie,
-- powrot kamery/UI. Inni gracze NIC nie widza (cue leci tylko do FireClient(firer)).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))
local NukeFxLib = require(script.Parent:WaitForChild("NukeFxLib"))

local AtomicStrikeController = {}
local LP = Players.LocalPlayer

-- Zegar MUSI zgadzac sie z serwerem (AtomicStrikeService.IMPACT_T = FLIGHT_T + CLOSEUP_T = 3.5s) — serwer
-- czysci fale we WLASNEJ klatce, niezaleznie od tego co robi ten kontroler (anti-exploit/lag safety).
local FLIGHT_T = 2.5 -- rakieta spada, kamera ja sledzi z bliska
local CLOSEUP_T = 1.0 -- twarde ciecie na kadr bazy, rakieta konczy lot w kadrze
local TOTAL_FALL = FLIGHT_T + CLOSEUP_T
local EXPLOSION_T = 3.0 -- grzyb + shockwave nad juz pusta mapa
local BAR_SCALE = 0.12
local SKY_H = 260
local SIDE_X = 42
local ROCKET_LEN = 9

-- CFrame rakiety: nos (-X) skierowany wzdluz `dir` (jak ArtilleryFxController.rocketCf)
local function rocketLookCf(pos, dir)
	local right = -dir.Unit
	local up0 = Vector3.yAxis
	local back = right:Cross(up0)
	if back.Magnitude < 0.02 then up0 = Vector3.xAxis; back = right:Cross(up0) end
	back = back.Unit
	local up = back:Cross(right).Unit
	return CFrame.fromMatrix(pos, right, up)
end

local function loadRocketMeshPart()
	local root = ReplicatedStorage:FindFirstChild("WR_RocketModels")
	local model = root and root:FindFirstChild("WR_Rocket_Booster")
	if not model then
		return nil
	end
	if model:IsA("Model") then
		return model.PrimaryPart or model:FindFirstChildWhichIsA("MeshPart", true)
	elseif model:IsA("MeshPart") then
		return model
	end
	return nil
end

local function mkRocketModel()
	local tmpl = loadRocketMeshPart()
	local rocket
	if tmpl then
		rocket = tmpl:Clone()
		local k = ROCKET_LEN / math.max(rocket.Size.X, 0.01)
		rocket.Size = rocket.Size * k
	else
		rocket = Instance.new("Part")
		rocket.Size = Vector3.new(ROCKET_LEN, 1.6, 1.6)
		rocket.Color = Color3.fromRGB(90, 96, 62)
		rocket.Material = Enum.Material.Metal
	end
	rocket.Anchored = true; rocket.CanCollide = false; rocket.CanQuery = false; rocket.CanTouch = false; rocket.CastShadow = false
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(rocket.Size.X * 0.45, 0.4, 0); a0.Parent = rocket
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(rocket.Size.X * 0.45, -0.4, 0); a1.Parent = rocket
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0; tr.Attachment1 = a1; tr.Lifetime = 0.5; tr.LightEmission = 0.6
	tr.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(120, 120, 120))
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0) })
	tr.FaceCamera = true; tr.Parent = rocket
	rocket.Parent = NukeFxLib.fxFolder()
	return rocket
end

-- ── UI: bary + blysk ──
local cutGui, topBar, botBar, flashFrame, glowFrame
local function ensureCutGui()
	if cutGui and cutGui.Parent then
		return
	end
	local pg = LP:WaitForChild("PlayerGui")
	cutGui = Instance.new("ScreenGui")
	cutGui.Name = "WR_AtomicFx"; cutGui.ResetOnSpawn = false; cutGui.IgnoreGuiInset = true
	cutGui.DisplayOrder = 500 -- nad wszystkim (WR_WaveFx=400, WR_SalvoBanner=450, WR_StrikeFlash=350)
	cutGui.Parent = pg

	topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1, 0, 0, 0); topBar.Position = UDim2.new(0, 0, 0, 0)
	topBar.BackgroundColor3 = Color3.new(0, 0, 0); topBar.BorderSizePixel = 0; topBar.Parent = cutGui

	botBar = Instance.new("Frame")
	botBar.AnchorPoint = Vector2.new(0, 1)
	botBar.Size = UDim2.new(1, 0, 0, 0); botBar.Position = UDim2.new(0, 0, 1, 0)
	botBar.BackgroundColor3 = Color3.new(0, 0, 0); botBar.BorderSizePixel = 0; botBar.Parent = cutGui

	flashFrame = Instance.new("Frame")
	flashFrame.Size = UDim2.fromScale(1, 1); flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	flashFrame.BackgroundTransparency = 1; flashFrame.BorderSizePixel = 0; flashFrame.ZIndex = 5; flashFrame.Parent = cutGui

	-- glowFrame: pelnoekranowa "kopula swiatla" jako GUI (nie 3D part) — gwarantuje ze pochlania caly
	-- ekran NIEZALEZNIE od pozycji kamery. 3D lightDome zawodzil bo kamera stoi ~139 studow od epicentrum,
	-- czyli WEWNATRZ 720-studowej kuli — backface culling od srodka renderuje ja jako niewidoczna.
	glowFrame = Instance.new("Frame")
	glowFrame.Size = UDim2.fromScale(1, 1); glowFrame.BackgroundColor3 = Color3.fromRGB(255, 232, 180)
	glowFrame.BackgroundTransparency = 1; glowFrame.BorderSizePixel = 0; glowFrame.ZIndex = 4; glowFrame.Parent = cutGui
end

-- ── ukrywanie/przywracanie calego UI gracza (poza WR_WaveFx — baner "WAVE CLEARED" ma zyc wlasnym zyciem) ──
local _hiddenGuis = {}
local function hideUI()
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	_hiddenGuis = {}
	for _, g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") and g ~= cutGui and g.Name ~= "WR_WaveFx" and g.Enabled then
			g.Enabled = false
			table.insert(_hiddenGuis, g)
		end
	end
end
local function restoreUI()
	for _, g in ipairs(_hiddenGuis) do
		if g.Parent then g.Enabled = true end
	end
	_hiddenGuis = {}
end

local _busy = false
local function runCutscene(impactPos: Vector3, corePos: Vector3, enemyBasePos: Vector3)
	if _busy then
		return
	end
	_busy = true
	ensureCutGui()
	hideUI()

	local cam = Workspace.CurrentCamera
	local prevType = cam.CameraType
	local prevCF = cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable

	topBar.Size = UDim2.new(1, 0, 0, 0)
	botBar.Size = UDim2.new(1, 0, 0, 0)
	flashFrame.BackgroundTransparency = 1
	glowFrame.BackgroundTransparency = 1
	TweenService:Create(topBar, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, BAR_SCALE, 0) }):Play()
	TweenService:Create(botBar, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, BAR_SCALE, 0) }):Play()

	-- RAKIETA: caly spadek trwa TOTAL_FALL (3.5s) — kamera jedynie zmienia ktory kadr pokazuje
	local rocket = mkRocketModel()
	local startP = impactPos + Vector3.new(SIDE_X, SKY_H, math.random(-15, 15))
	local dir = (impactPos - startP).Unit
	rocket:PivotTo(rocketLookCf(startP, dir))
	local cfv = Instance.new("CFrameValue")
	cfv.Value = rocket:GetPivot()
	local moveConn = cfv:GetPropertyChangedSignal("Value"):Connect(function()
		if rocket.Parent then rocket:PivotTo(cfv.Value) end
	end)
	TweenService:Create(cfv, TweenInfo.new(TOTAL_FALL, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = rocketLookCf(impactPos, dir) }):Play()

	-- KAMERA FAZA 1 (0..FLIGHT_T): sledzi rakiete z bliska
	local chaseConn
	chaseConn = RunService.RenderStepped:Connect(function()
		if not rocket.Parent then return end
		local rp = rocket:GetPivot().Position
		cam.CFrame = CFrame.lookAt(rp + Vector3.new(-SIDE_X * 0.5, 14, 30), rp)
	end)

	local wideConn
	local _shakeUntil, _shakeMag, _shakeDur = 0, 0, 0.5
	local function shake(mag, dur)
		dur = dur or 0.5
		_shakeMag = math.max(_shakeMag, mag)
		_shakeUntil = os.clock() + dur
		_shakeDur = dur
	end

	task.delay(FLIGHT_T, function()
		if chaseConn then chaseConn:Disconnect(); chaseConn = nil end
		-- KAMERA FAZA 2: TWARDE CIECIE, zza bazy gracza, z gory/z boku, patrzac na epicentrum — tak zeby
		-- padajace jednostki wroga (miedzy corePos a enemyBasePos) byly widoczne w kadrze (nie tylko baza).
		-- awayDir = kierunek OD wroga W STRONE bazy gracza -> kamera stoi DALEJ w tym kierunku (za baza).
		local awayDir = corePos - enemyBasePos
		awayDir = Vector3.new(awayDir.X, 0, awayDir.Z)
		if awayDir.Magnitude < 1 then awayDir = Vector3.new(0, 0, 1) end
		awayDir = awayDir.Unit
		local sideDir = awayDir:Cross(Vector3.yAxis).Unit
		local BACK_DIST, SIDE_OFF, CAM_H = 55, 45, 70
		local camPos = corePos + awayDir * BACK_DIST + sideDir * SIDE_OFF + Vector3.new(0, CAM_H, 0)
		local wideCF = CFrame.lookAt(camPos, impactPos)
		wideConn = RunService.RenderStepped:Connect(function()
			if os.clock() < _shakeUntil then
				local remain = (_shakeUntil - os.clock()) / _shakeDur
				local m = _shakeMag * remain * remain
				cam.CFrame = wideCF
					* CFrame.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
					* CFrame.Angles((math.random() - 0.5) * m * 0.01, (math.random() - 0.5) * m * 0.01, 0)
			else
				cam.CFrame = wideCF
			end
		end)
	end)

	task.delay(TOTAL_FALL, function()
		moveConn:Disconnect(); cfv:Destroy()
		if rocket.Parent then rocket:Destroy() end
		-- IMPACT: blysk w TEJ KLATCE — serwer w tej samej chwili (wlasny task.delay(IMPACT_T)) czysci fale.
		-- Kontroler NIC serwerowi nie zglasza — wylacznie oprawa.
		flashFrame.BackgroundTransparency = 0
		TweenService:Create(flashFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
		-- glowFrame: pelnoekranowa "kopula" w GUI, harmonogram lustrzany do lightDome (narosc 0.5s,
		-- trzymanie do t=2.2s, zgaszenie do t=3.0s=EXPLOSION_T) — w przeciwienstwie do 3D kuli GWARANTUJE
		-- ze caly ekran tonie w swietle bez wzgledu na pozycje kamery.
		glowFrame.BackgroundTransparency = 1
		TweenService:Create(glowFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.15 }):Play()
		task.delay(2.2, function()
			if glowFrame then
				TweenService:Create(glowFrame, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
			end
		end)
		shake(4.5, EXPLOSION_T)
		NukeFxLib.bigMushroom(impactPos)
	end)

	task.delay(TOTAL_FALL + EXPLOSION_T, function()
		if wideConn then wideConn:Disconnect(); wideConn = nil end
		cam.CameraType = prevType
		cam.CFrame = prevCF
		TweenService:Create(topBar, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.new(1, 0, 0, 0) }):Play()
		TweenService:Create(botBar, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.new(1, 0, 0, 0) }):Play()
		task.delay(0.4, function()
			restoreUI()
			_busy = false
		end)
	end)
end

function AtomicStrikeController.start()
	Net.get("AtomicStrikeCue").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table"
			or typeof(payload.impactPos) ~= "Vector3"
			or typeof(payload.corePos) ~= "Vector3"
			or typeof(payload.enemyBasePos) ~= "Vector3"
		then
			return
		end
		local ok, err = pcall(runCutscene, payload.impactPos, payload.corePos, payload.enemyBasePos)
		if not ok then
			warn("[AtomicStrikeController] cutscenka padla: " .. tostring(err))
		end
	end)
end

return AtomicStrikeController
