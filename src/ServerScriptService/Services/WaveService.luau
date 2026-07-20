--!nonstrict
-- ServerScriptService/Services/WaveService.luau
-- SLICE (zadanie 6 forward-minimal): tylko GetPhase — BuildService pyta o faze przed stawianiem.
-- Domyslna faza runu = Building. Pelny cykl fali (StartWave, spawn puli, kill counter,
-- WaveEnded, summary, nagroda, faza WaveActive/Summary) = zadanie 7.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))

local WaveService = {}

local _phase: { [Player]: string } = {} -- player -> Enums.RunPhase (domyslnie Building)

function WaveService.GetPhase(player: Player): string
	return _phase[player] or Enums.RunPhase.Building
end

function WaveService.Init() end

function WaveService.Start()
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		_phase[player] = nil
	end)
end

return WaveService
