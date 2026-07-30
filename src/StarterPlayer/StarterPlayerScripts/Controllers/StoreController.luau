--!nonstrict
-- StarterPlayerScripts/Controllers/StoreController.luau  (KLIENT)
-- Sklep: klik -> chowa CALY HUD (RAZEM z monetami — kupno za Robux) + pokazuje panel GRAFIKA.
-- UI robi ziomek w Studio (StarterGui.Store, place-owned). Tu TYLKO: toggle Canvas.Visible +
-- podpiecie jego przycisku X. Nic nie tworzymy w jego frame (tresc/produkty = osobny etap).
local Players = game:GetService("Players")

local HudOverlay = require(script.Parent:WaitForChild("HudOverlay"))

local StoreController = {}
local LP = Players.LocalPlayer
local _canvas = nil -- StarterGui.Store.Canvas (panel grafika)

local function closePanel()
	if _canvas then _canvas.Visible = false end
	HudOverlay.exit() -- przywroc HUD
end

local function openPanel()
	if not _canvas then return end
	HudOverlay.enter(false) -- schowaj CALY HUD razem z monetami (Robux, nie coiny)
	_canvas.Visible = true
end

function StoreController.start()
	local pg = LP:WaitForChild("PlayerGui")
	local store = pg:WaitForChild("Store", 15) -- ScreenGui grafika (place-owned)
	if not store then
		warn("[StoreController] brak PlayerGui.Store — UI sklepu grafika nie znaleziony")
		return
	end
	store.ResetOnSpawn = false -- respawn nie ma zresetowac referencji (nie-wizualne, na klonie runtime)

	_canvas = store:WaitForChild("Canvas", 5)
	if not _canvas then
		warn("[StoreController] Store bez Canvas — nie podepne sklepu")
		return
	end
	_canvas.Visible = false -- start: schowany (HUD ziomka ustawia to samo)

	local x = _canvas:FindFirstChild("X")
	if x and x:IsA("GuiButton") then
		x.MouseButton1Click:Connect(closePanel)
	end

	StoreController.Open = openPanel -- HUD ziomka (SideButtons.Store) wola to
	StoreController.Close = closePanel
end

return StoreController
