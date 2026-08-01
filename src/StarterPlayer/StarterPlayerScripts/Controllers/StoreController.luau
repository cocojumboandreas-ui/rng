--!nonstrict
-- StarterPlayerScripts/Controllers/StoreController.luau  (KLIENT)
-- Sklep: klik -> chowa CALY HUD (RAZEM z monetami — kupno za Robux) + pokazuje panel GRAFIKA.
-- UI robi ziomek w Studio (StarterGui.Store, place-owned). Tu: toggle Canvas.Visible + przycisk X +
-- INTERAKTYWNOSC: tylko przyciski "Buy"/"Buy1" (z cena Robux) klikalne; reszta klikalnych elementow
-- (karty-TextButtony, ikony) -> martwe (Active=false). Klik Buy -> PromptPurchase wg atrybutu
-- GamePassId/ProductId na przycisku lub karcie-przodku (ID doda designer/PurchaseService po bramce).
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

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

-- ID zakupu z atrybutu (przycisk Buy lub karta-przodek): GamePassId / ProductId. Brak ID -> nic.
local function promptPurchase(buyBtn)
	local node = buyBtn
	while node and node ~= _canvas do
		local gp = node:GetAttribute("GamePassId")
		if type(gp) == "number" and gp > 0 then
			MarketplaceService:PromptGamePassPurchase(LP, gp)
			return
		end
		local pr = node:GetAttribute("ProductId")
		if type(pr) == "number" and pr > 0 then
			MarketplaceService:PromptProductPurchase(LP, pr)
			return
		end
		node = node.Parent
	end
	-- brak ID (placeholder) — Robux prompt ruszy gdy designer ustawi atrybut na produkcie
end

-- tylko przyciski Buy/Buy1 klikalne; reszta GuiButton w Content -> nieklikalna i bez feedbacku
local function wireInteractivity()
	local content = _canvas:FindFirstChild("ContentStroke")
	content = content and content:FindFirstChild("Content")
	if not content then
		return
	end
	for _, d in ipairs(content:GetDescendants()) do
		if d:IsA("GuiButton") then
			local isBuy = string.match(d.Name, "^Buy") ~= nil
			d.Active = isBuy
			d.AutoButtonColor = isBuy
			d.Selectable = isBuy
			if isBuy then
				d.MouseButton1Click:Connect(function()
					promptPurchase(d)
				end)
			else
				d:SetAttribute("WR_NoHover", true) -- UIHoverBinder pomija te karty (bez hover/press)
				-- posprzataj ewentualny feedback UIHoverBindera (gdyby zdazyl podpiac przed nami)
				local sc = d:FindFirstChild("WR_HoverScale")
				if sc then sc:Destroy() end
				local hs = d:FindFirstChild("WR_HoverStroke")
				if hs then hs:Destroy() end
			end
		end
	end
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

	wireInteractivity()

	StoreController.Open = openPanel -- HUD ziomka (SideButtons.Store) wola to
	StoreController.Close = closePanel
end

return StoreController
