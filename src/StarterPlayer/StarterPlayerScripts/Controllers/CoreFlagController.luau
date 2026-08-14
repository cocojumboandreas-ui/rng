--!nonstrict
-- StarterPlayerScripts/Controllers/CoreFlagController.luau  (KLIENT)
-- Flaga ZAMIAST neonowego bloku rdzenia: przechyla sie plynnie wg HP core'a (Net.CoreHP, serwer autorytatywny).
-- Kotwica WR_CoreAnchor zostaje logicznie (cel/kolizja/HP) — tu TYLKO wizual zamiennika.
-- Krzywa: angle(pct) = 90*(1-pct)^1.5 (100%=0 prosto .. 0%=90 plasko), obrot wokol podstawy drzewca
-- (FlagGroundCFrame — pozycja+yaw ku faceDirection zapisane przy stawianiu flagi w Studio) do TYLU.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local CoreFlagController = {}
local LP = Players.LocalPlayer

local FALL_DURATION = 0.9 -- tween [s] do plaskiej pozycji (hp=0) — dluzszy, dramatyczny upadek
local FALL_HOLD = 0.6 -- [s] PO dojechaniu do plaskiej: ignoruj kolejne CoreHP. finishRun woła _core.ResetHP
	-- NATYCHMIAST po CoreDestroyed (nastepny run) — bez tej blokady upadek nigdy nie bylby widoczny.
local LIVE_DURATION = 0.45 -- tween [s] dla zwyklych zmian HP w trakcie fali

local _flag, _pole, _groundCF, _halfH = nil, nil, nil, nil
local _angleValue = Instance.new("NumberValue")
_angleValue.Value = 0
local _activeTween = nil
local _holdUntil = 0

-- WR: FlagGroundCFrame (per-plot, zapisane przy stawianiu w Studio) ma yaw ustawiony ~rownolegle
-- do faceDirection plota (potwierdzone na 5/6 placow) — plotno flagi jednak stoi wtedy BOKIEM
-- (krawedziowo) do gracza zamiast NAPRZECIW. Korekta o -90 stopni (90+180, na zyczenie druga
-- strona plotna) w kodzie (nie per-plac w Studio) naprawia to spojnie na wszystkich placach
-- jednym miejscem, bo dziala na SUROWYM
-- _groundCF przed pochyleniem HP — przechyl (pitch) dalej liczy sie wzgledem nowej, poprawionej ramki.
local FLAG_YAW_FIX = CFrame.Angles(0, math.rad(-90), 0)

local function angleFor(pct: number): number
	pct = math.clamp(pct, 0, 1)
	return 90 * (1 - pct) ^ 1.5
end

-- FALOWANIE (czysto kosmetyczne, klient-only): sztywny MeshPart bez riga wiec prawdziwe
-- uginanie tkaniny odpada — zludzenie wiatru robimy lekkim obrotem calego platna wokol
-- osi drzewca (lokalny Y pivotu flagi = origin obrotu, bo PrimaryPart to drzewce), plynnie
-- tam-i-z-powrotem w nieskonczonosc przez TweenService (NumberValue kata, Sine InOut,
-- RepeatCount=-1, Reverses=true) — NIE recznym sin() w RenderStepped. Changed-signal tego
-- NumberValue przelicza CFrame platna z aktualnego _flag:GetPivot() (ktore juz zawiera
-- biezacy pitch HP) — nakladane NA WIERZCH przechylu, nie zastepuje ani nie zeruje PivotTo
-- z apply(). Dziala na WSZYSTKICH flagach naraz (nie tylko wlasnej), bo to czysto wizualna
-- dekoracja terenu, nie stan gry. Grid.003 + Grid.004 (dwie niemal wspollinowe warstwy tego
-- samego platna) faluja RAZEM identyczna transformacja — gdyby falowaly niezaleznie,
-- minimalny rozjazd geometrii powodowalby przenikanie siatek (z-fighting) miedzy warstwami.
local WAVE_CANVAS_NAMES = { "Meshes/TedyThings_Grid.003", "Meshes/TedyThings_Grid.004" }
local WAVE_AMPLITUDE_DEG = 4 -- subtelne wychylenie (+/-)
local WAVE_HALF_PERIOD = 1.3 -- [s] czas przejscia w jedna strone (Sine InOut)
local _waveFlags = {} -- [flagModel] = { angleValue:NumberValue, parts:{ {part=MeshPart, baseOffset=CFrame} } }

local function updateWaveVisual(flagModel: Instance, data)
	if not flagModel.Parent then
		return
	end
	local pivot = flagModel:GetPivot()
	local hingeWave = CFrame.Angles(0, math.rad(data.angleValue.Value), 0)
	for _, entry in ipairs(data.parts) do
		entry.part.CFrame = pivot * hingeWave * entry.baseOffset
	end
end

local function registerWaveFlag(flagModel: Instance)
	if _waveFlags[flagModel] then
		return
	end
	local pivot = flagModel:GetPivot()
	local parts = {}
	for _, partName in ipairs(WAVE_CANVAS_NAMES) do
		local part = flagModel:FindFirstChild(partName)
		if part then
			table.insert(parts, { part = part, baseOffset = pivot:ToObjectSpace(part.CFrame) })
		end
	end
	if #parts == 0 then
		return
	end

	local angleValue = Instance.new("NumberValue")
	angleValue.Value = -WAVE_AMPLITUDE_DEG
	local data = { angleValue = angleValue, parts = parts }
	_waveFlags[flagModel] = data

	angleValue:GetPropertyChangedSignal("Value"):Connect(function()
		updateWaveVisual(flagModel, data)
	end)
	updateWaveVisual(flagModel, data)

	-- offset fazy per-plac (deterministyczny z PlotId) zeby flagi nie falowaly idealnie w unisono —
	-- DelayTime przesuwa tylko START tweena, dalej leci wlasny nieskonczony Reverses=true cykl.
	local plotId = flagModel:GetAttribute("PlotId") or 0
	local startDelay = (plotId * 0.577) % WAVE_HALF_PERIOD

	local tween = TweenService:Create(
		angleValue,
		TweenInfo.new(WAVE_HALF_PERIOD, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, startDelay),
		{ Value = WAVE_AMPLITUDE_DEG }
	)
	tween:Play()
	data.tween = tween
end

local function apply()
	if not (_flag and _pole and _groundCF and _halfH) then
		return
	end
	local cf = _groundCF * FLAG_YAW_FIX * CFrame.Angles(math.rad(_angleValue.Value), 0, 0) * CFrame.new(0, _halfH, 0)
	_flag:PivotTo(cf)
end

local function findFlag()
	local myPlot = LP:GetAttribute("PlotId")
	for _, f in ipairs(CollectionService:GetTagged("WR_CoreFlag")) do
		if f:GetAttribute("PlotId") == myPlot then
			return f
		end
	end
	return nil
end

local function ensureFlag(): boolean
	if _flag and _flag.Parent then
		return true
	end
	local f = findFlag()
	if not f then
		return false
	end
	_flag = f
	_pole = f.PrimaryPart
	_groundCF = f:GetAttribute("FlagGroundCFrame")
	_halfH = f:GetAttribute("FlagPoleHalfHeight")
	return _pole ~= nil and _groundCF ~= nil and _halfH ~= nil
end

local function setAngle(target: number, duration: number)
	if _activeTween then
		_activeTween:Cancel()
	end
	local isFall = target >= 89.9
	local tw = TweenService:Create(
		_angleValue,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, isFall and Enum.EasingDirection.In or Enum.EasingDirection.Out),
		{ Value = target }
	)
	_activeTween = tw
	tw:Play()
end

_angleValue:GetPropertyChangedSignal("Value"):Connect(apply)

function CoreFlagController.start()
	Net.get("CoreHP").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then
			return
		end
		if p.plotId ~= nil and p.plotId ~= LP:GetAttribute("PlotId") then
			return
		end
		if not ensureFlag() then
			return
		end
		local now = os.clock()
		if now < _holdUntil then
			return -- flaga wlasnie legla plasko — nie przerywaj chwili zanim gracz ja zobaczy
		end
		local maxHp = p.maxHp
		local pct = (maxHp and maxHp > 0) and math.clamp((p.hp or maxHp) / maxHp, 0, 1) or 1
		local target = angleFor(pct)
		local isFall = target >= 89.9
		setAngle(target, isFall and FALL_DURATION or LIVE_DURATION)
		if isFall then
			_holdUntil = now + FALL_DURATION + FALL_HOLD
		end
	end)

	-- flaga/plot moga pojawic sie po dolaczeniu — retry az znajdziemy wlasna
	task.spawn(function()
		for _ = 1, 60 do
			if ensureFlag() then
				apply()
				break
			end
			task.wait(0.3)
		end
	end)
	CollectionService:GetInstanceAddedSignal("WR_CoreFlag"):Connect(function(f)
		registerWaveFlag(f)
		if ensureFlag() then
			apply()
		end
	end)

	-- falowanie: WSZYSTKIE flagi na mapie, nie tylko wlasna (dekoracja terenu) — kazda dostaje
	-- wlasny nieskonczony TweenService cykl (patrz registerWaveFlag), nic tu wiecej nie trzeba spinac.
	for _, f in ipairs(CollectionService:GetTagged("WR_CoreFlag")) do
		registerWaveFlag(f)
	end
end

return CoreFlagController
