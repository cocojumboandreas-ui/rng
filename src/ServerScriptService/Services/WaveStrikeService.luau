--!nonstrict
-- ServerScriptService/Services/WaveStrikeService.luau
-- Strike'i galezi bojowej (Player PRO): Military Convoy / Air Raid / Nuke. Po odblokowaniu wezla w drzewie
-- odpalaja sie AUTOMATYCZNIE podczas fali, na cooldownie (SkillEffectConfig.strikes). Uderzaja AoE w skupisko
-- wrogow gracza (CombatService.AreaDamage) i wysylaja Net.WaveStrike do klienta (oprawa wizualna).
-- Serwer-autorytatywny (dmg TU; klient tylko FX). deps: CombatService, WaveService, ProfileService, PlotService.
-- Military Convoy (kind="convoy") jest WYJATKIEM: nie liczy dmg/FX tutaj, tylko odpala
-- ConvoyStrikeService.RequestConvoy (jeep-konwoj, wlasna geometria/FX/dmg) — patrz fireStrike().
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local WaveStrikeService = {}

local _combat, _wave, _profile, _plot, _convoy = nil, nil, nil, nil, nil
local _strikeNet = nil
local _salvoNet = nil
local _cd = {} -- player -> {kind -> pozostaly cooldown [s]}
local _acc = 0

local function specs()
	return (GameConfig.SkillEffect and GameConfig.SkillEffect.strikes) or {}
end

local function ownsNode(player, nodeId)
	local data = _profile and _profile.GetProfile(player)
	return (data and data.skills and (data.skills[nodeId] or 0) > 0) or false
end

local function plotIdOf(player)
	local plot = _plot and _plot.GetPlot(player)
	return (plot and plot.plotId) or 0
end

-- Odpal strike danego rodzaju: AoE w skupisko + Net FX. Zwraca liczbe TRAFIONYCH (0 gdy brak celu na planszy).
-- SALWA (nalot artyleryjski): 8 rakiet 2k dmg w skupisko, HP spada NA UDERZENIU (task.delay = stagger + fall).
local SALVO = { count = 8, stagger = 0.12, fall = 0.8, dmg = 2000, radius = 16 }
local function runSalvo(player)
	if not _combat then return 0 end
	local center = _combat.PickStrikeTarget(player)
	if not center then return 0 end
	if _strikeNet and typeof(player) == "Instance" then
		_strikeNet:FireClient(player, { kind = "airRaid", plotId = plotIdOf(player), pos = center, radius = SALVO.radius })
	end
	local totalKills = 0
	for i = 1, SALVO.count do
		local ang = math.random() * 2 * math.pi
		local r = math.random() * (SALVO.radius * 0.6)
		local impact = center + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
		local last = (i == SALVO.count)
		task.delay((i - 1) * SALVO.stagger + SALVO.fall, function()
			if _combat then
				local _, k = _combat.AreaDamage(player, impact, SALVO.radius, SALVO.dmg)
				totalKills += (k or 0)
			end
			if last and _salvoNet and totalKills >= 3 and typeof(player) == "Instance" then
				_salvoNet:FireClient(player, { kills = totalKills }) -- "×N" nagroda za skutecznosc
			end
		end)
	end
	return SALVO.count
end

local function fireStrike(player, kind, spec)
	if kind == "convoy" then
		-- PRZEPIETE na jeep-konwoj: ConvoyStrikeService liczy wlasna geometrie/dmg/FX (ConvoyCue),
		-- WaveStrike Net / SpreadDamage tutaj sie juz NIE uzywa dla convoy.
		if not _convoy then
			return 0
		end
		return _convoy.RequestConvoy(player) and 1 or 0
	end
	if not _combat then
		return 0
	end
	if kind == "airRaid" then return runSalvo(player) end -- nalot = salwa 8 rakiet (nowy FX + 2k/rakieta)
	local target = _combat.PickStrikeTarget(player)
	if not target then
		return 0
	end
	local hit
	if spec.spread then
		hit = _combat.SpreadDamage(player, spec.dmg or 0)
	else
		hit = _combat.AreaDamage(player, target, spec.radius or 10, spec.dmg or 0)
	end
	if _strikeNet and typeof(player) == "Instance" then
		_strikeNet:FireClient(player, { kind = kind, plotId = plotIdOf(player), pos = target, radius = spec.radius or 10 })
	end
	return hit
end

-- Petla: tylko gracze W FALI; per rodzaj strike'a odliczaj cooldown i odpalaj gdy wezel posiadany.
local function step(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		if _wave and _wave.GetPhase(player) == Enums.RunPhase.WaveActive then
			local timers = _cd[player]
			if not timers then
				timers = {}
				_cd[player] = timers
			end
			for kind, spec in pairs(specs()) do
				if ownsNode(player, spec.node) then
					local t = timers[kind]
					if t == nil then
						t = spec.cooldown or 30 -- pierwszy strike po pelnym cooldownie
					end
					t -= dt
					if t <= 0 then
						local hit = fireStrike(player, kind, spec)
						-- brak celu (pusta plansza) -> nie marnuj pelnego cooldownu, sprobuj ponownie za chwile
						t = (hit > 0) and (spec.cooldown or 30) or math.min(2, spec.cooldown or 30)
					end
					timers[kind] = t
				end
			end
		else
			_cd[player] = nil -- poza fala: reset (nastepna fala od pelnego cooldownu)
		end
	end
end

function WaveStrikeService.Init() end

function WaveStrikeService.Start()
	_combat = ServiceRegistry.get("CombatService")
	_wave = ServiceRegistry.get("WaveService")
	_profile = ServiceRegistry.get("ProfileService")
	_plot = ServiceRegistry.get("PlotService")
	_convoy = ServiceRegistry.get("ConvoyStrikeService")
	_strikeNet = Net.get("WaveStrike")
	_salvoNet = Net.get("SalvoResult")

	RunService.Heartbeat:Connect(function(dt)
		_acc += dt
		if _acc >= 0.2 then -- ~5 Hz wystarczy dla cooldownow sekundowych (tanie)
			step(_acc)
			_acc = 0
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		_cd[player] = nil
	end)
end

-- Dev/skill trigger salwy (nalot). Zwraca liczbe rakiet (0 gdy brak celu na planszy).
function WaveStrikeService.RunSalvo(player)
	return runSalvo(player)
end

-- Hooki TYLKO do testow.
function WaveStrikeService._ForceStrikeForTest(player, kind) -- ignoruje cooldown/faze; zwraca liczbe trafionych
	local spec = specs()[kind]
	if not spec then
		return -1
	end
	return fireStrike(player, kind, spec)
end
function WaveStrikeService._InjectForTest(deps)
	_combat, _wave, _profile, _plot = deps.combat, deps.wave, deps.profile, deps.plot
	if deps.convoy ~= nil then
		_convoy = deps.convoy
	end
	if deps.strikeNet ~= nil then
		_strikeNet = deps.strikeNet
	end
end

return WaveStrikeService
