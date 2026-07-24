--!nonstrict
-- StarterPlayerScripts/Controllers/AttentionBob.luau  (KLIENT)
-- Plynne KOLYSANIE (rotation sway) przyciskow Roll + Sklep, zeby przyciagac uwage gracza.
-- Realizacja: powtarzalny tween (Sine InOut, Reverses, nieskonczony) na wlasnosci Rotation.
-- Rotation jest niezalezna od UIScale (UIHoverBinder/QuickScale) i nie rusza Size/Position (layout ok).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local AttentionBob = {}
local LP = Players.LocalPlayer

local AMP = 6.0 -- amplituda (stopnie): kolysze od -AMP do +AMP
local HALF = 0.5 -- czas polowy kolysniecia (s) -> pelny cykl ~1s ("co sekunde")

local function sway(btn, startNeg)
	if not (btn and btn:IsA("GuiObject")) then return end
	local from = startNeg and -AMP or AMP
	local to = startNeg and AMP or -AMP
	btn.Rotation = from
	local info = TweenInfo.new(HALF, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true) -- inf + reverses = ciagle kolysanie
	TweenService:Create(btn, info, { Rotation = to }):Play()
end

function AttentionBob.start()
	local pg = LP:WaitForChild("PlayerGui")
	local sb = pg:WaitForChild("SideButtons", 15)
	if not sb then return end
	local function path(...)
		local o = sb
		for _, n in ipairs({ ... }) do o = o and o:FindFirstChild(n) end
		return o
	end
	sway(path("BottomCanvas", "Buttons", "Roll"), true) -- Roll: -6 -> +6 ...
	sway(path("LeftCanvas", "Buttons", "Store"), false) -- Sklep: +6 -> -6 ... (przeciwfaza)
end

return AttentionBob
