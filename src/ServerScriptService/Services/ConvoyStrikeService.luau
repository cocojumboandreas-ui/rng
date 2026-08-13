--!nonstrict
-- ServerScriptService/Services/ConvoyStrikeService.luau
-- KONWOJ 4 jeepow: serwer-autorytatywna faza WJAZD (offplot z LEWEJ -> polowa drogi baza-rdzen,
-- ten sam "stopPos" co dawniej) -> POSTOJ+OGIEN (bez zmian: FIRE_T, wiezyczki aktywne caly ten czas)
-- -> WYJAZD (polowa drogi -> offplot w PRAWO) -> znika. Formacja: 4 jeepy w LINII w poprzek
-- szerokosci placu, SYMETRYCZNIE wzgledem srodkowej kolumny (2 POZA siatka, 2 NA siatce) — linia
-- jedzie W CALOSCI jako sztywna formacja wzdluz WLASNEJ osi (lateralAxis, prostopadlej do sciezki
-- baza-wroga<->rdzen), NIE wzdluz fwd jak dawny system ciezarowki.
-- Miniguny na jeepach reuzywaja 1:1 dmg/namierzanie z GameConfig.Units.dual_minigun — patrz
-- CombatService.GetMobileTurrets: rownolegly rejestr do GridService.placements, karmiony ZYWA
-- pozycja jeepa TYLKO na czas fazy ognia (stacjonarna, jak dawniej — poza tym oknem nic nie strzela).
-- Klient (ConvoyController) samodzielnie renderuje wjazd/postoj/wyjazd wg tych samych stalych
-- (linePos/lateralAxis/offsets/entryExitOffset/driveT/fireT) — serwer NIE czeka na klienta, wlasny
-- task.delay.
-- Wejscia: RequestConvoy(player) (auto-trigger n106 z WaveStrikeService.step()) ORAZ sieciowy
-- ConvoyStrike event (dev-button, manualny test) — oba leca przez ten sam onRequest.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local ConvoyStrikeService = {}

local _wave, _plot = nil, nil
local _strikeReq, _cueNet = nil, nil
local _busy = {} -- player -> true przez CALA sekwencje (wjazd+ogien+wyjazd), debounce/anty-spam
local _active = {} -- player -> {turrets={{unitId,pos},...}, fireUntil} — TYLKO podczas fazy ognia (postoj)

-- MUSI zgadzac sie z klientem (ConvoyController) — obie strony dostaja driveT/fireT W CUE (serwer
-- liczy je z DRIVE_SPEED + zywej geometrii), wiec klient nie musi znac DRIVE_SPEED osobno.
local FIRE_T = 5 -- potwierdzone: dlugosc fazy ostrzalu (jeepy STOJA caly ten czas, wiezyczki aktywne OD RAZU po wjezdzie)
local DRIVE_SPEED = 30 -- study/s, predkosc wjazdu/wyjazdu konwoju (kosmetyczna stala tempa jazdy)

local UNIT_ID = "dual_minigun"

local function plotIdOf(player)
	local plot = _plot and _plot.GetPlot(player)
	return (plot and plot.plotId) or 0
end

-- Formacja: linia na polowie drogi miedzy baza wroga (pathNodes[1] = brama spawnu) a rdzeniem
-- gracza — POTWIERDZONE zywym pomiarem (PlotService.GetPlot), nie zgadywane. Os formacji (lateral)
-- = PROSTOPADLA do kierunku sciezki (faceDirection obrocony 90 stopni) — jeepy staja W POPRZEK
-- placu I JADA wzdluz TEJ SAMEJ osi (lewo->srodek->prawo), nie wzdluz fwd.
-- Offsety liczone z ZYWEJ geometrii siatki (GameConfig.Grid.width/cellSize), NIE hardkodowane:
--   half = polowa szerokosci placu w studach (srodek kolumny 5 -> krawedz)
--   insideOffset  = 1.5 komorki OD krawedzi do srodka -> wyraznie NA siatce
--   outsideOffset = 1 komorka POZA krawedzia -> wyraznie POZA siatka
--   entryExitOffset = half + outsideOffset + 1 komorka -> caly wjazd/wyjazd calkowicie POZA placem
-- (skrajny jeep formacji, +outsideOffset od srodka, wciaz zostaje offplot z zapasem 1 komorki)
-- 4 pozycje wzgledem srodka = {-outside, -inside, +inside, +outside} -> symetryczne wzgledem srodka.
local function convoyFormation(player)
	local plot = _plot and _plot.GetPlot(player)
	if not plot then
		return nil
	end
	local corePos = plot.coreCFrame.Position
	local enemyBasePos = (plot.pathNodes and plot.pathNodes[1] and plot.pathNodes[1].Position) or corePos
	local linePos = corePos:Lerp(enemyBasePos, 0.5)
	local fwd = plot.faceDirection or Vector3.new(0, 0, 1)
	local lateralAxis = Vector3.new(fwd.Z, 0, -fwd.X)
	if lateralAxis.Magnitude < 0.01 then
		lateralAxis = Vector3.new(1, 0, 0)
	end
	lateralAxis = lateralAxis.Unit

	local width = GameConfig.Grid.width
	local cellSize = GameConfig.Grid.cellSize
	local half = (width * cellSize) / 2
	local insideOffset = half - cellSize * 1.5
	local outsideOffset = half + cellSize * 1
	local entryExitOffset = half + outsideOffset + cellSize

	local offsets = { -outsideOffset, -insideOffset, insideOffset, outsideOffset }

	return {
		linePos = linePos,
		lateralAxis = lateralAxis,
		offsets = offsets,
		entryExitOffset = entryExitOffset,
		driveT = entryExitOffset / DRIVE_SPEED,
	}
end

-- Wywolywane przez CombatService co tick symulacji (TYLKO gdy gracz ma aktywny konwoj W FAZIE OGNIA,
-- czyli PO wjezdzie i PRZED wyjazdem) — zwraca {{unitId="dual_minigun", pos=Vector3}, ...} albo nil.
-- Pozycje sa STALE (jeepy stoja przez cala faze ognia, formacja sie nie porusza W TYM oknie).
function ConvoyStrikeService.GetMobileTurrets(player)
	local a = _active[player]
	if not a or os.clock() >= a.fireUntil then
		return nil
	end
	return a.turrets
end

-- Zwraca true gdy konwoj faktycznie wystartowal (false: juz w trakcie / zla faza / brak geometrii placu).
local function onRequest(player)
	if _busy[player] then
		return false
	end
	if not _wave or _wave.GetPhase(player) ~= Enums.RunPhase.WaveActive then
		return false
	end
	local formation = convoyFormation(player)
	if not formation then
		return false
	end
	_busy[player] = true

	if _cueNet then
		_cueNet:FireClient(player, {
			linePos = formation.linePos,
			lateralAxis = formation.lateralAxis,
			offsets = formation.offsets,
			entryExitOffset = formation.entryExitOffset,
			driveT = formation.driveT,
			fireT = FIRE_T,
			plotId = plotIdOf(player),
		})
	end

	local turrets = {}
	for i, off in ipairs(formation.offsets) do
		turrets[i] = { unitId = UNIT_ID, pos = formation.linePos + formation.lateralAxis * off }
	end

	-- Wiezyczki aktywuja sie DOPIERO po wjezdzie (driveT), gasna PRZED wyjazdem (driveT+FIRE_T).
	-- Strazniki `_busy[player]`: gdyby gracz wyszedl w trakcie (PlayerRemoving czysci _busy/_active
	-- od razu), spozniony task.delay NIE ma prawa wskrzesic stanu.
	task.delay(formation.driveT, function()
		if _busy[player] then
			_active[player] = { turrets = turrets, fireUntil = os.clock() + FIRE_T }
		end
	end)

	task.delay(formation.driveT + FIRE_T, function()
		_active[player] = nil
	end)

	task.delay(formation.driveT * 2 + FIRE_T, function()
		_busy[player] = nil
	end)

	return true
end

-- Publiczne wejscie do auto-triggera (WaveStrikeService.step(), po odblokowaniu n106, na cooldownie
-- z SkillEffectConfig.strikes.convoy) — ten sam kod co dev-button/sieciowy ConvoyStrike event.
function ConvoyStrikeService.RequestConvoy(player)
	return onRequest(player)
end

-- Hook TYLKO do testow (jak DevService._IsDevForTest) — omija sieciowy round-trip klient->serwer.
function ConvoyStrikeService._RequestForTest(player)
	onRequest(player)
end

function ConvoyStrikeService.Init() end

function ConvoyStrikeService.Start()
	_wave = ServiceRegistry.get("WaveService")
	_plot = ServiceRegistry.get("PlotService")
	_strikeReq = Net.get("ConvoyStrike")
	_cueNet = Net.get("ConvoyCue")

	_strikeReq.OnServerEvent:Connect(onRequest)

	Players.PlayerRemoving:Connect(function(player)
		_busy[player] = nil
		_active[player] = nil
	end)
end

return ConvoyStrikeService
