--!nonstrict
-- ServerScriptService/Services/AtomicStrikeService.luau
-- Ultimate ATOMOWKA: klient prosi (AtomicStrike), serwer planuje WLASNY, niezalezny od klienta zegar
-- uderzenia (IMPACT_T, mirror klienckiej cutscenki AtomicStrikeController: FLIGHT_T+CLOSEUP_T). W klatce
-- uderzenia serwer czysci CALA aktywna fale przez WaveService.InstantClearWave (ISTNIEJACA sciezka
-- nagrody/WaveEnded/nastepna-fali). Cutscenka NIE decyduje o zabojstwach — tylko oprawa.
-- Serwer-autorytatywny: clear TU; klient tylko FX (cue wylacznie do gracza ktory odpalil).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))

local AtomicStrikeService = {}

local _wave, _plot, _core = nil, nil, nil
local _strikeReq, _cueNet = nil, nil
local _busy = {} -- player -> true podczas trwania wlasnej cutscenki (debounce, anty-spam)

-- MUSI zgadzac sie z klientem (AtomicStrikeController FLIGHT_T + CLOSEUP_T) — serwer sam planuje
-- wlasny task.delay, NIE czeka na zaden sygnal zwrotny klienta (anti-exploit/lag safety).
local IMPACT_T = 3.5
-- Pelna dlugosc KLIENCKIEJ cutscenki (TOTAL_FALL+EXPLOSION_T w AtomicStrikeController) — _busy MUSI zyc
-- do konca cutscenki, nie tylko do impaktu, inaczej drugie zadanie w oknie 3.5-6.5s zaliczyloby CICHY
-- (bez cutscenki, klient go zignoruje wlasnym _busy) drugi clear fali.
local CUTSCENE_T = 6.5

local function plotIdOf(player)
	local plot = _plot and _plot.GetPlot(player)
	return (plot and plot.plotId) or 0
end

-- Epicentrum NIE na rdzeniu gracza — POMIEDZY baza wroga (pierwszy pathNode = brama spawnu, patrz
-- PlotService.gateSpawnPoint) a rdzeniem gracza. IMPACT_FRAC=0.5 => dokladnie w polowie; promien
-- wybuchu (AtomicStrikeController.bigMushroom) jest celowo wiekszy niz ta odleglosc, wiec baza
-- gracza i tak zostaje objeta kopula/grzybem.
local IMPACT_FRAC = 0.5
local function strikeGeometry(player)
	local plot = _plot and _plot.GetPlot(player)
	local cf = plot and plot.coreCFrame
	local corePos = cf and cf.Position or Vector3.new(0, 0, 0)
	local enemyBasePos = plot and plot.pathNodes and plot.pathNodes[1] and plot.pathNodes[1].Position or corePos
	local impactPos = corePos:Lerp(enemyBasePos, IMPACT_FRAC)
	return impactPos, corePos, enemyBasePos
end

local function onRequest(player)
	if _busy[player] then
		return
	end
	if not _wave or _wave.GetPhase(player) ~= Enums.RunPhase.WaveActive then
		return
	end
	_busy[player] = true
	local impactPos, corePos, enemyBasePos = strikeGeometry(player)
	if _core then
		_core.SetInvulnerable(player, true) -- "plansza zamrozona": rdzen nie ginie w oknie lotu rakiety
	end
	if _cueNet then
		_cueNet:FireClient(player, {
			impactPos = impactPos,
			corePos = corePos,
			enemyBasePos = enemyBasePos,
			plotId = plotIdOf(player),
		})
	end
	task.delay(IMPACT_T, function()
		if player.Parent and _wave then
			_wave.InstantClearWave(player)
		end
		if _core then
			_core.SetInvulnerable(player, false)
		end
	end)
	task.delay(CUTSCENE_T, function()
		_busy[player] = nil
	end)
end

function AtomicStrikeService.Init() end

function AtomicStrikeService.Start()
	_wave = ServiceRegistry.get("WaveService")
	_plot = ServiceRegistry.get("PlotService")
	_core = ServiceRegistry.get("CoreService")
	_strikeReq = Net.get("AtomicStrike")
	_cueNet = Net.get("AtomicStrikeCue")

	_strikeReq.OnServerEvent:Connect(onRequest)

	Players.PlayerRemoving:Connect(function(player)
		_busy[player] = nil
	end)
end

return AtomicStrikeService
