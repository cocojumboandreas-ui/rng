--!nonstrict
-- ServerScriptService/Services/WaveStrikeService.luau
-- Strike'i galezi bojowej (Player PRO): Military Convoy / Air Raid / Nuke. Po odblokowaniu wezla w drzewie
-- odpalaja sie AUTOMATYCZNIE podczas fali, na cooldownie (SkillEffectConfig.strikes). Uderzaja AoE w skupisko
-- wrogow gracza (CombatService.AreaDamage) i wysylaja Net.WaveStrike do klienta (oprawa wizualna).
-- Serwer-autorytatywny (dmg TU; klient tylko FX). deps: CombatService, WaveService, ProfileService, PlotService.
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

local _combat, _wave, _profile, _plot = nil, nil, nil, nil
local _strikeNet = nil
local _cd: { [any]: { [string]: number } } = {} -- player -> {kind -> pozostaly cooldown [s]}
local _acc = 0

local function specs()
	return (GameConfig.SkillEffect and GameConfig.SkillEffect.strikes) or {}
end

local function ownsNode(player, nodeId: string): boolean
	local data = _profile and _profile.GetProfile(player)
	return (data and data.skills and (data.skills[nodeId] or 0) > 0) or false
end

local function plotIdOf(player): number
	local plot = _plot and _plot.GetPlot(player)
	return (plot and plot.plotId) or 0
end

-- Odpal strike danego rodzaju: AoE w skupisko + Net FX. Zwraca liczbe TRAFIONYCH (0 gdy brak celu na planszy).
local function fireStrike(player, kind: string, spec): number
	if not _combat then
		return 0
	end
	local target = _combat.PickStrikeTarget(player)
	if not target then
		return 0
	end
	local hit = _combat.AreaDamage(player, target, spec.radius or 10, spec.dmg or 0)
	if _strikeNet and typeof(player) == "Instance" then
		_strikeNet:FireClient(player, { kind = kind, plotId = plotIdOf(player), pos = target, radius = spec.radius or 10 })
	end
	return hit
end

-- Petla: tylko gracze W FALI; per rodzaj strike'a odliczaj cooldown i odpalaj gdy wezel posiadany.
local function step(dt: number)
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
	_strikeNet = Net.get("WaveStrike")

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
	if deps.strikeNet ~= nil then
		_strikeNet = deps.strikeNet
	end
end

return WaveStrikeService
