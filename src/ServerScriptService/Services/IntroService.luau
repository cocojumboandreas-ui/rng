--!nonstrict
-- ServerScriptService/Services/IntroService.luau
-- Minimalny serwis (Faza 1B, Krok 3 cutscenki intro): trzyma i udostepnia flage hasSeenIntro.
-- Cala logika samej cutscenki (kamera/brama/marsz/pomijanie) jest w 100% po stronie klienta
-- (IntroController/CutsceneController) — serwer TYLKO przechowuje stan w profilu.
-- deps: ProfileService.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))

local IntroService = {}

local _profile = nil
local _plot = nil

-- serwerowy zegar "pod biela" (WLASNY, NIE czeka na klienta) — Krok 5 finalu cutscenki intro.
-- Wzorzec AtomicStrikeService: klient prosi, serwer odmierza SWOJ czas, robi PivotTo, dopiero
-- POTEM potwierdza klientowi -> klient gasi flash tylko po tym potwierdzeniu (zero szwu).
local TELEPORT_T = 1.0
local _finaleBusy = {}

function IntroService.Init() end

function IntroService.Start()
	_profile = ServiceRegistry.get("ProfileService")
	_plot = ServiceRegistry.get("PlotService")

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

	-- Net.IntroTeleportHome (RemoteEvent, C->S) — finalowy teleport spod bieli (Krok 5)
	Net.get("IntroTeleportHome").OnServerEvent:Connect(function(player)
		if _finaleBusy[player] then
			return
		end
		_finaleBusy[player] = true
		task.delay(TELEPORT_T, function()
			if player.Parent and _plot then
				_plot.ReturnToPlot(player)
			end
			if player.Parent then
				Net.get("IntroTeleportHomeDone"):FireClient(player)
			end
			_finaleBusy[player] = nil
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_finaleBusy[player] = nil
	end)
end

return IntroService
