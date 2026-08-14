--!nonstrict
-- StarterPlayerScripts/Controllers/AutoRollController.luau  (KLIENT)
-- Auto-roll przez NATYWNY flow packa Roll: perCycle reeli RÓWNOLEGLE, pack czeka az WSZYSTKIE skoncza,
-- potem znowu (petla, bardzo plynne). Wlaczany gdy gracz ma Automatic Roll (n2). Serwer (RollService)
-- podpiety pod RequestRollRemoteFunction -> AutoRollColumns (nasz RNG, inventory+index, consume). Regen trzyma rolki > 0.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local AutoRollController = {}
local AUTO_NODE = "n2"

function AutoRollController.start()
	local RollClient = require(ReplicatedStorage:WaitForChild("Roll"):WaitForChild("RollClient"))
	local owned = false

	-- WR: persystencja preferencji auto ON/OFF w ProfileStore (Net.SetAutoRollEnabled, C->S fire-and-forget).
	-- Kazda zmiana _isAuto (klik gracza LUB nasze programowe ustawienie ponizej) -> zapisz na serwerze.
	RollClient.setIsAutoChangedCallback(function(isAuto)
		pcall(function()
			Net.get("SetAutoRollEnabled"):FireServer(isAuto)
		end)
	end)

	-- czekaj az gracz ma n2 (poll co 4s; kupno w drzewku bez broadcastu)
	task.spawn(function()
		local persistedEnabled = true
		while not owned do
			local ok, st = pcall(function()
				return Net.get("GetSkillState"):InvokeServer()
			end)
			if ok and st and st.ranks and (st.ranks[AUTO_NODE] or 0) > 0 then
				owned = true
				if st.autoRollEnabled == false then
					persistedEnabled = false -- WR: gracz mial auto wylaczone przed wyjsciem -> zostaw wylaczone
				end
			else
				task.wait(4)
			end
		end
		RollClient.setIsCompact(true) -- auto = MALY reel na gorze-srodku
		RollClient.setIsAuto(persistedEnabled) -- WR: respektuj zapisana preferencje (domyslnie ON przy pierwszym odblokowaniu)
		if persistedEnabled then
			pcall(function()
				RollClient.requestRoll()
			end) -- start
		end
	end)

	-- watchdog: restart TYLKO gdy auto GENUINIE stanelo (nie kreci sie przez >=3s z rzedu). NIE reaguj na
	-- chwilowe okno miedzy cyklami (requestRoll czeka na serwer ~100ms) — inaczej odpalasz DRUGI rownolegly
	-- loop packa i masz 4 kolumny naraz zamiast 2.
	task.spawn(function()
		local idle = 0
		while true do
			task.wait(1)
			if owned and RollClient.isAuto and RollClient.isAuto() then
				if RollClient.isRolling() then
					idle = 0
				else
					idle += 1
					if idle >= 3 then
						idle = 0
						pcall(function()
							RollClient.requestRoll()
						end)
					end
				end
			else
				idle = 0
			end
		end
	end)
end

return AutoRollController
