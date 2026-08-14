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
-- (krawedziowo) do gracza zamiast NAPRZECIW. Korekta o stala 90 stopni w LEWO w kodzie (nie per-plac
-- w Studio) naprawia to spojnie na wszystkich placach jednym miejscem, bo dziala na SUROWYM
-- _groundCF przed pochyleniem HP — przechyl (pitch) dalej liczy sie wzgledem nowej, poprawionej ramki.
local FLAG_YAW_FIX = CFrame.Angles(0, math.rad(90), 0)

local function angleFor(pct: number): number
	pct = math.clamp(pct, 0, 1)
	return 90 * (1 - pct) ^ 1.5
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
	CollectionService:GetInstanceAddedSignal("WR_CoreFlag"):Connect(function()
		if ensureFlag() then
			apply()
		end
	end)
end

return CoreFlagController
