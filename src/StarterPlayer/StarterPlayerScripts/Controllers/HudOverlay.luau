--!nonstrict
-- StarterPlayerScripts/Controllers/HudOverlay.luau  (KLIENT — modul pomocniczy)
-- Chowa/przywraca HUD ziomka (SideButtons) na czas nakladki na caly ekran (Index / Sklep).
-- keepCoins=true -> zostaw monety (lewy gorny) widoczne (Index pokazuje stan konta; Sklep = false).
-- Zapamietuje oryginalna widocznosc kazdego elementu i przywraca ja na exit.
local Players = game:GetService("Players")

local HudOverlay = {}
local LP = Players.LocalPlayer
local _saved = {}

local function framesToHide(keepCoins)
	local sb = LP.PlayerGui:FindFirstChild("SideButtons")
	if not sb then return {} end
	local function path(...)
		local o = sb
		for _, n in ipairs({ ... }) do o = o and o:FindFirstChild(n) end
		return o
	end
	local list = {
		path("RightCanvas"), -- przyciski fali
		path("BottomCanvas"), -- Rolka + Zbuduj + Umiejetnosci
		path("LeftCanvas", "Buttons"), -- Sklep + Indeks
		path("BottomLeftCanvas", "OfflineEarns"), -- zarobki offline
		path("TopCanvas"), -- info fali
	}
	if not keepCoins then
		list[#list + 1] = path("LeftCanvas", "Coins") -- Sklep: bez monet (kupno za Robux)
	end
	return list
end

function HudOverlay.enter(keepCoins)
	HudOverlay.exit() -- gdyby cos zostalo z poprzedniej nakladki
	for _, f in ipairs(framesToHide(keepCoins)) do
		if f and f:IsA("GuiObject") then
			_saved[#_saved + 1] = { f, f.Visible }
			f.Visible = false
		end
	end
end

function HudOverlay.exit()
	for _, rec in ipairs(_saved) do
		if rec[1] and rec[1].Parent then rec[1].Visible = rec[2] end
	end
	_saved = {}
end

return HudOverlay
