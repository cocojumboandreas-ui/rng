--!nonstrict
-- StarterPlayerScripts/Controllers/AutoWaveController.luau  (KLIENT)
-- Wpina DESIGNEROWY przycisk "Auto Wave" (StarterGui.SideButtons.RightCanvas.Buttons.AutoWave, place-owned)
-- w logike auto-startu runu. NIE klonuje juz StartWave (stary klon-guzik usuniety) — steruje gotowym przyciskiem.
-- Widoczny TYLKO gdy gracz ma skill Automatic Wave (n5). Toggle: gdy ON i NIE trwa fala (Building / po przegranej)
-- -> auto-fire StartWave. Fale leca ciagiem, wiec to auto-start runu. Serwer i tak waliduje (StartWave tylko z Building).
-- deps: Net (GetSkillState, StartWave, WaveProgress, RunSummary).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local AutoWaveController = {}
local AUTO_NODE = "n5" -- Automatic Wave

function AutoWaveController.start()
	local lp = Players.LocalPlayer
	local pg = lp:WaitForChild("PlayerGui")
	local sb = pg:WaitForChild("SideButtons", 20)
	if not sb then
		return
	end
	local rc = sb:WaitForChild("RightCanvas", 10)
	local buttons = rc and rc:WaitForChild("Buttons", 10)
	local auto = buttons and buttons:WaitForChild("AutoWave", 10) -- GOTOWY przycisk artysty (nie klonujemy)
	if not auto then
		return
	end
	local btn = auto:FindFirstChild("Button") or auto:FindFirstChildWhichIsA("GuiButton", true)
	if not btn then
		return
	end

	local _on = false
	local _owned = false

	-- Napis "Auto Wave" siedzi w zagniezdzonych TextLabelach (Button.Text + cien Text.Text) -> ustaw WSZYSTKIE.
	local function refresh()
		local t = _on and "Auto: ON" or "Auto Wave"
		for _, d in ipairs(auto:GetDescendants()) do
			if d:IsA("TextLabel") then
				d.Text = t
			end
		end
	end

	-- WIDOCZNOSC: pokaz dopiero gdy gracz ma n5 (artysta ustawil Visible=true -> chowamy do odblokowania).
	-- Poll co 4s az odblokuje (kupno w drzewku bez broadcastu).
	auto.Visible = false
	task.spawn(function()
		while not _owned do
			local ok, st = pcall(function()
				return Net.get("GetSkillState"):InvokeServer()
			end)
			if ok and st and st.ranks and (st.ranks[AUTO_NODE] or 0) > 0 then
				_owned = true
				auto.Visible = true
				refresh()
				break
			end
			task.wait(4)
		end
	end)

	btn.MouseButton1Click:Connect(function()
		if not _owned then
			return
		end
		_on = not _on
		refresh()
	end)

	-- Stan fali: WaveProgress = fala trwa; RunSummary = koniec runu (wracamy do Building).
	local _waveActive = false
	Net.get("WaveProgress").OnClientEvent:Connect(function()
		_waveActive = true
	end)
	Net.get("RunSummary").OnClientEvent:Connect(function()
		_waveActive = false
	end)

	-- PETLA AUTO: gdy ON, odblokowane i NIE w fali -> odpal StartWave (serwer ruszy run; fale leca ciagiem).
	task.spawn(function()
		while true do
			if _on and _owned and not _waveActive then
				pcall(function()
					Net.get("StartWave"):FireServer()
				end)
				task.wait(1.5) -- daj serwerowi ustawic faze WaveActive zanim sprobujemy znowu
			end
			task.wait(0.5)
		end
	end)
end

return AutoWaveController
