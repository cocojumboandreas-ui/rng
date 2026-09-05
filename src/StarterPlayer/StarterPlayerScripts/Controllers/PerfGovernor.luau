--!nonstrict
-- StarterPlayerScripts/Controllers/PerfGovernor.luau  (KLIENT — serwis adaptacyjnej wydajnosci)
-- Mierzy FPS W CZASIE RZECZYWISTYM i dobiera TIER jakosci 1..5 (Ultra..Potato) z HISTEREZA
-- (szybko schodzi gdy tnie, wolno wraca gdy plynnie) tak, zeby gra byla plynna nawet na
-- najslabszych urzadzeniach. Aplikuje trzy warstwy:
--   1) SILNIK: Lighting.GlobalShadows + post-efekty (Bloom/SunRays/DoF/Blur) off na niskich tierach.
--   2) PerfSettings.applyTier: warstwa AUTO przelacznikow (soldierAnim/attackAnim/showOthers/coinAnim)
--      + BUDZETY FX (mnozniki liczby czastek: confetti/rain/coins/heavy). Reczne przelaczniki panelu ⚙
--      zostaja nietkniete — auto tylko DOKRECA w dol (eff = reczny AND auto).
--   3) Atrybuty LocalPlayer (WR_PerfTier / WR_RainMul / WR_FillerRefresh) — czyta je place-owned
--      pack Roll (deszcz koniczyn, przebudowa viewportow filler w reelu).
-- DEBUG: LocalPlayer:SetAttribute("WR_ForceTier", n) wymusza tier (nil = auto).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local PerfSettings = require(script.Parent:WaitForChild("PerfSettings"))

local PerfGovernor = {}
local LP = Players.LocalPlayer

-- ── TIERY: co gasimy na ktorym poziomie ──────────────────────────────────────
-- auto: klucze PerfSettings wylaczane przez governor. budgets: mnozniki liczby czastek FX.
-- shadows=false dopiero od T3 (cienie to duzy koszt na slabych GPU). fillerRefresh=false od T4
-- (reel przestaje przebudowywac modele viewport co cykl — znane zrodlo scinek przy auto-rollu).
local TIERS = {
	-- animDist: mnoznik progu dystansu kamery (bazowo 150 studow), za ktorym wrogowie NIE animuja
	-- konczyn/bobu i NIE aktualizuja paskow HP (EnemyRenderController) — ruch po sciezce zostaje.
	[1] = { name = "Ultra", shadows = true, auto = {}, budgets = { confetti = 1, rain = 1, coins = 1, heavy = 1, animDist = 1 }, fillerRefresh = true },
	[2] = { name = "High", shadows = true, auto = {}, budgets = { confetti = 0.7, rain = 0.66, coins = 0.66, heavy = 0.8, animDist = 0.8 }, fillerRefresh = true },
	[3] = { name = "Medium", shadows = false, auto = { attackAnim = false }, budgets = { confetti = 0.5, rain = 0.45, coins = 0.5, heavy = 0.5, animDist = 0.7 }, fillerRefresh = true },
	[4] = { name = "Low", shadows = false, auto = { attackAnim = false, showOthers = false, coinAnim = false }, budgets = { confetti = 0.3, rain = 0.25, coins = 0.25, heavy = 0.3, animDist = 0.6 }, fillerRefresh = false },
	-- DOPAMINA CHRONIONA: liczby obrazen/HEADSHOT/special-roll/aura zwyciezcy/banner odkrycia/count-up monet
	-- NIE sa ciete na ZADNYM tierze (jednorazowe momenty nagrody = sedno gry). Tniemy tylko AMBIENT/masowke.
	-- rain=0.2 na Potato (nie 0): koniczyna = moment dopaminowy, pack trzyma min. 3 sztuki.
	[5] = { name = "Potato", shadows = false, auto = { attackAnim = false, showOthers = false, coinAnim = false, soldierAnim = false }, budgets = { confetti = 0.15, rain = 0.2, coins = 0, heavy = 0.2, animDist = 0.5 }, fillerRefresh = false },
}

-- ── histereza ────────────────────────────────────────────────────────────────
local DROP_FPS = 27 -- srednia 1s ponizej -> licz w dol
local RAISE_FPS = 52 -- srednia 1s powyzej -> licz w gore
local DROP_AFTER = 2 -- sekund slabych z rzedu -> tier w dol (reaguj szybko)
local RAISE_AFTER = 8 -- sekund dobrych z rzedu -> tier w gore (wracaj ostroznie, bez oscylacji)

local _tier = 1
local _postFx = {} -- [instancja post-efektu] = oryginalny Enabled (do przywrocenia)
local _shadows0 = nil -- oryginalny GlobalShadows

local function applyEngine(t)
	if _shadows0 == nil then _shadows0 = Lighting.GlobalShadows end
	Lighting.GlobalShadows = t.shadows and _shadows0 or false
	-- post-efekty: zgas na tierach bez cieni, przywroc oryginal na wysokich
	for _, fx in ipairs(Lighting:GetChildren()) do
		if fx:IsA("PostEffect") then
			if _postFx[fx] == nil then _postFx[fx] = fx.Enabled end
			fx.Enabled = t.shadows and _postFx[fx] or false
		end
	end
end

local function applyTier(n)
	n = math.clamp(n, 1, #TIERS)
	if n == _tier then return end
	_tier = n
	local t = TIERS[n]
	applyEngine(t)
	PerfSettings.applyTier(n, t.auto, t.budgets)
	LP:SetAttribute("WR_PerfTier", n)
	LP:SetAttribute("WR_RainMul", t.budgets.rain or 1)
	LP:SetAttribute("WR_FillerRefresh", t.fillerRefresh ~= false)
	print(("[PerfGovernor] tier -> %d (%s)"):format(n, t.name))
end

function PerfGovernor.start()
	-- stan startowy = Ultra (atrybuty ustawione, zeby pack mial co czytac od 1. klatki)
	LP:SetAttribute("WR_PerfTier", 1)
	LP:SetAttribute("WR_RainMul", 1)
	LP:SetAttribute("WR_FillerRefresh", true)

	local frames, accum = 0, 0
	local lowStreak, highStreak = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		frames += 1
		accum += dt
		if accum < 1 then return end
		local fps = frames / accum
		frames, accum = 0, 0

		-- DEBUG override (testy/QA): wymuszony tier ma priorytet nad pomiarem
		local forced = LP:GetAttribute("WR_ForceTier")
		if typeof(forced) == "number" then
			applyTier(forced)
			return
		end

		if fps < DROP_FPS then
			lowStreak += 1
			highStreak = 0
			if lowStreak >= DROP_AFTER then
				lowStreak = 0
				applyTier(_tier + 1)
			end
		elseif fps > RAISE_FPS then
			highStreak += 1
			lowStreak = 0
			if highStreak >= RAISE_AFTER then
				highStreak = 0
				applyTier(_tier - 1)
			end
		else
			lowStreak, highStreak = 0, 0 -- strefa neutralna: trzymaj obecny tier
		end
	end)
end

return PerfGovernor
