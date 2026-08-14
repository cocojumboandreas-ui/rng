--!nonstrict
-- ServerScriptService/Services/IntroService.luau
-- Minimalny serwis (Faza 1B, Krok 3 cutscenki intro): trzyma i udostepnia flage hasSeenIntro.
-- Cala logika samej cutscenki (kamera/brama/marsz/pomijanie) jest w 100% po stronie klienta
-- (IntroController/CutsceneController) — serwer TYLKO przechowuje stan w profilu.
-- deps: ProfileService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))

local IntroService = {}

local _profile = nil

function IntroService.Init() end

function IntroService.Start()
	_profile = ServiceRegistry.get("ProfileService")

	-- Net.GetIntroState (RemoteFunction, C->S) -> {hasSeenIntro:boolean}
	Net.get("GetIntroState").OnServerInvoke = function(player)
		local data = _profile.GetProfile(player)
		return { hasSeenIntro = (data and data.hasSeenIntro) == true }
	end

	-- Net.MarkIntroSeen (RemoteEvent, C->S) — gracz obejrzal (do konca) lub pominal intro
	Net.get("MarkIntroSeen").OnServerEvent:Connect(function(player)
		local data = _profile.GetProfile(player)
		if data then
			data.hasSeenIntro = true
		end
	end)
end

return IntroService
