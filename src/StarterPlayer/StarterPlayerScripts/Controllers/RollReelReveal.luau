--!nonstrict
-- RollReelReveal (Content, CLIENT): slot-machine ("jednoreki bandyta") reveal.
--
-- PURE CLIENT JUICE. The winning unit is decided by RollService on the SERVER
-- (Random.new server-side) and arrives via RollResult. This module ONLY animates
-- landing on that result -- it never rolls anything. Keep RollService untouched.
--
-- Smoothness comes from two choices:
--   1. The reel scrolls with ONE TweenService tween (Quint Out) -- no chained
--      position tweens, so there is no velocity seam to hitch on. The "clunk" at
--      the end is a SCALE pop on the winner card (separate property, starts from
--      rest), not a second position tween.
--   2. Reel cards are cheap. Pass `iconFor` to render ImageLabels (butter-smooth);
--      only the final reveal uses a ViewportFrame for the 3D model that sways.
--
-- Wire it where you currently trigger the starburst reveal:
--
--   RollReelReveal.init({
--       parent      = playerGui,
--       unitsFolder = ReplicatedStorage.Assets.Units,     -- models for reveal (+ card fallback)
--       resolveTier = function(rarityN) return { color = Color3, name = "Rare" } end,
--       starburstId = "rbxassetid://<your starburst>",     -- reuse the reveal one
--       iconFor     = function(unitId) return "rbxassetid://..." end, -- OPTIONAL: smooth icon reel
--   })
--   rollResult.OnClientEvent:Connect(function(result)      -- result: { unitId, rarityN, ... }
--       RollReelReveal.play(result)
--   end)

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RollReel = require(ReplicatedStorage.Framework.UI.RollReel)
local Wobble = require(ReplicatedStorage.Framework.UI.Wobble)
local GameConfig = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig"))

local RollReelReveal = {}

-- ---- tuning (all the "feel" knobs live here) --------------------------------
local TUNING = {
	cardWidth = 148, -- pitch: 132 card + 16 padding
	cardCount = 34, -- cards per spin (decoys + winner). Fewer = cheaper. Icons let you go higher.
	winnerIndex = 30, -- where the real winner sits (leave a few cards after it)
	duration = 3.1, -- spin seconds (szybciej)
	easingStyle = Enum.EasingStyle.Quint, -- Quint/Quart Out = long fast run, clean settle
	jitter = 26, -- +/- px off dead-center for a natural stop (keep small)
	landPopScale = 1.14, -- winner card scale pop on land
	landPopTime = 0.16,
}
local CARD_PADDING = 16
local NEUTRAL = Color3.fromRGB(70, 74, 84)
-- kolory koniczyn kaskady mnoznika (2x zielony -> 128x bialy)
local MUT_COLOR = {
	[2] = Color3.fromRGB(90, 220, 90), [4] = Color3.fromRGB(80, 160, 255), [8] = Color3.fromRGB(190, 110, 255),
	[16] = Color3.fromRGB(255, 205, 80), [32] = Color3.fromRGB(255, 130, 60), [64] = Color3.fromRGB(90, 235, 235),
	[128] = Color3.fromRGB(255, 255, 255),
}
local REVEAL_SIZE = UDim2.fromOffset(480, 560)
local REVEAL_SIZE_SMALL = UDim2.fromOffset(48, 56)

local cfg = {}
local refs = {}
local state = { rolling = false, wobble = nil, winnerScale = nil, auto = false }

-- BlurEffect rozmywa TYLKO swiat 3D (nie GUI) -> tlo zamazane, item (ViewportFrame) ostry na 1. planie.
local Lighting = game:GetService("Lighting")
local function setRevealBlur(on: boolean)
	local blur = Lighting:FindFirstChild("WR_RevealBlur")
	if on then
		if not blur then
			blur = Instance.new("BlurEffect")
			blur.Name = "WR_RevealBlur"
			blur.Parent = Lighting
		end
		TweenService:Create(blur, TweenInfo.new(0.25), { Size = 20 }):Play()
	elseif blur then
		TweenService:Create(blur, TweenInfo.new(0.25), { Size = 0 }):Play()
	end
end

-- ---- helpers ----------------------------------------------------------------

-- Frames a 3D model inside a ViewportFrame. Used for the final reveal (and for
-- reel cards only when `iconFor` is not supplied).
local function buildViewport(model: Instance, parent: Instance): ViewportFrame
	local vpf = Instance.new("ViewportFrame")
	vpf.BackgroundTransparency = 1
	local cam = Instance.new("Camera")
	vpf.CurrentCamera = cam
	cam.Parent = vpf

	local clone = model:Clone()
	clone.Parent = vpf

	local cframe, size = clone:GetBoundingBox()
	local maxExtent = math.max(size.X, size.Y, size.Z)
	local dist = maxExtent * 1.7
	cam.CFrame = CFrame.new(cframe.Position + Vector3.new(0, size.Y * 0.08, dist), cframe.Position)

	vpf.Parent = parent
	return vpf
end

-- Resolves a unitId to a template Model, via modelProvider (preferred) or unitsFolder.
-- The returned model is a TEMPLATE; this module clones it before display.
local function resolveModel(unitId: string): Instance?
	if cfg.modelProvider then
		return cfg.modelProvider(unitId)
	elseif cfg.unitsFolder then
		return cfg.unitsFolder:FindFirstChild(unitId)
	end
	return nil
end

-- BEZ RAMEK: karta = poswiata (kolor rzadkosci) + model 3D + "1 in N" (gora) + nazwa (dol).
local function makeCard(model: Instance, glowColor: Color3, rarityN: number?, name: string?): Frame
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(250, TUNING.cardWidth - CARD_PADDING) -- pion: szeroka + niska (wys = pitch)
	card.BackgroundTransparency = 1

	-- aura/poswiata za itemem (bez tekstury: skalowany starburst ✦)
	local glow = Instance.new("TextLabel")
	glow.BackgroundTransparency = 1
	glow.AnchorPoint = Vector2.new(0.5, 0.5); glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(0.85, 1.5)
	glow.Font = Enum.Font.GothamBlack; glow.Text = "✦"; glow.TextScaled = true
	glow.TextColor3 = glowColor; glow.TextTransparency = 0.3; glow.ZIndex = 1; glow.Parent = card

	local vpf = buildViewport(model, card)
	vpf.AnchorPoint = Vector2.new(0.5, 0.5)
	vpf.Position = UDim2.fromScale(0.5, 0.5)
	vpf.Size = UDim2.fromScale(0.6, 0.96)
	vpf.ZIndex = 2

	if rarityN then
		local odds = Instance.new("TextLabel")
		odds.AnchorPoint = Vector2.new(0.5, 0); odds.Position = UDim2.fromScale(0.5, 0.0); odds.Size = UDim2.fromScale(0.7, 0.22)
		odds.BackgroundTransparency = 1; odds.Font = Enum.Font.GothamBlack; odds.TextScaled = true
		odds.Text = "1 in " .. rarityN; odds.TextColor3 = glowColor; odds.ZIndex = 3; odds.Parent = card
		local os_ = Instance.new("UIStroke"); os_.Thickness = 2; os_.Color = Color3.new(0, 0, 0); os_.Parent = odds
	end
	if name then
		local nm = Instance.new("TextLabel")
		nm.AnchorPoint = Vector2.new(0.5, 1); nm.Position = UDim2.fromScale(0.5, 1.0); nm.Size = UDim2.fromScale(0.95, 0.18)
		nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextScaled = true
		nm.Text = name; nm.TextColor3 = Color3.new(1, 1, 1); nm.ZIndex = 3; nm.Parent = card
		local ns = Instance.new("UIStroke"); ns.Thickness = 2; ns.Color = Color3.new(0, 0, 0); ns.Parent = nm
	end

	return card
end

local function clearStrip()
	for _, child in refs.strip:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	state.winnerScale = nil
end

-- Kaskada mnoznika mutacji: koniczyny 2x -> 4x -> ... -> mult, wyskakuja po kolei nad itemem.
local function playMutationCascade(mult: number)
	local holder = refs.cascadeHolder
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local rungs = {}
	local m = 2
	while m <= mult do rungs[#rungs + 1] = m; m *= 2 end
	local n = #rungs
	for i, mv in ipairs(rungs) do
		local badge = Instance.new("Frame")
		badge.BackgroundTransparency = 1
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.new(0.5, (i - (n + 1) / 2) * 76, 0.5, 0)
		badge.Size = UDim2.fromOffset(16, 18)
		badge.ZIndex = 5; badge.Parent = holder
		local clover = Instance.new("TextLabel")
		clover.BackgroundTransparency = 1; clover.Size = UDim2.fromScale(1, 1); clover.Text = "🍀"
		clover.TextScaled = true; clover.TextColor3 = MUT_COLOR[mv] or Color3.new(1, 1, 1); clover.ZIndex = 5; clover.Parent = badge
		local mtxt = Instance.new("TextLabel")
		mtxt.BackgroundTransparency = 1; mtxt.Size = UDim2.fromScale(1, 0.55); mtxt.Position = UDim2.fromScale(0, 0.25)
		mtxt.Font = Enum.Font.GothamBlack; mtxt.Text = mv .. "x"; mtxt.TextScaled = true
		mtxt.TextColor3 = Color3.new(1, 1, 1); mtxt.ZIndex = 6; mtxt.Parent = badge
		local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = Color3.new(0, 0, 0); st.Parent = mtxt
		TweenService:Create(badge, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(74, 86) }):Play()
		task.wait(0.16)
	end
end

local function showReveal(model: Instance, rarityN: number, tier, displayName: string, mult: number?)
	refs.reveal.Visible = true
	refs.revealAura.ImageColor3 = tier.color
	-- swiecacy background za itemem: miekki krag (glow) + obracajacy sie starburst, kolor rzadkosci
	if not refs.revealGlow then
		refs.revealGlow = Instance.new("Frame")
		refs.revealGlow.BackgroundColor3 = Color3.new(1, 1, 1)
		refs.revealGlow.AnchorPoint = Vector2.new(0.5, 0.5); refs.revealGlow.Position = UDim2.fromScale(0.5, 0.46)
		refs.revealGlow.Size = UDim2.fromScale(0.9, 0.9); refs.revealGlow.ZIndex = 0; refs.revealGlow.Parent = refs.revealInner
		local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(1, 0); gc.Parent = refs.revealGlow
		local gg = Instance.new("UIGradient")
		gg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.55, 0.55), NumberSequenceKeypoint.new(1, 1) })
		gg.Rotation = 90; gg.Parent = refs.revealGlow
	end
	refs.revealGlow.BackgroundColor3 = tier.color
	if not refs.revealStar then
		refs.revealStar = Instance.new("TextLabel")
		refs.revealStar.BackgroundTransparency = 1
		refs.revealStar.AnchorPoint = Vector2.new(0.5, 0.5); refs.revealStar.Position = UDim2.fromScale(0.5, 0.46)
		refs.revealStar.Size = UDim2.fromScale(1.3, 1.3)
		refs.revealStar.Font = Enum.Font.GothamBlack; refs.revealStar.Text = "✦"; refs.revealStar.TextScaled = true
		refs.revealStar.ZIndex = 1; refs.revealStar.Parent = refs.revealInner
	end
	refs.revealStar.TextColor3 = tier.color
	refs.revealStar.TextTransparency = 0.12
	refs.revealStar.Rotation = 0
	TweenService:Create(refs.revealStar, TweenInfo.new(4, Enum.EasingStyle.Linear), { Rotation = 120 }):Play()
	refs.revealOdds.Text = string.format("1 in %d", rarityN)
	refs.revealOdds.TextColor3 = tier.color
	refs.revealName.Text = displayName

	if refs.revealVpf then
		refs.revealVpf:Destroy()
	end
	refs.revealVpf = buildViewport(model, refs.revealInner)
	refs.revealVpf.AnchorPoint = Vector2.new(0.5, 0.5)
	refs.revealVpf.Position = UDim2.fromScale(0.5, 0.46)
	refs.revealVpf.Size = UDim2.fromScale(0.5, 0.5)
	refs.revealVpf.ZIndex = 2

	-- pop-in (grows around center because AnchorPoint is 0.5,0.5)
	refs.revealInner.Size = REVEAL_SIZE_SMALL
	TweenService:Create(
		refs.revealInner,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = REVEAL_SIZE }
	):Play()

	-- start the idle sway once the pop-in settles; Wobble eases its amplitude in
	task.delay(0.2, function()
		if state.wobble then
			state.wobble:Stop()
		end
		-- szybszy, energiczny ruch (nie wolne kolysanie)
		state.wobble = Wobble.start(refs.revealInner, {
			rotationAmplitude = 3, rotationSpeed = 6, bobAmplitude = 6, bobSpeed = 5, easeIn = 0.12,
		})
	end)

	-- kaskada mnoznika (koniczyny 2x->..->mult) gdy item ma mutacje
	if mult and mult > 1 then
		task.spawn(playMutationCascade, mult)
	else
		for _, c in ipairs(refs.cascadeHolder:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
	end
end

-- ---- public API -------------------------------------------------------------

function RollReelReveal.init(config)
	cfg = config

	local gui = Instance.new("ScreenGui")
	gui.Name = "RollReelReveal"
	gui.DisplayOrder = 50 -- nad HUD (20): przyciemnienie zakrywa HUD, zostaje pasek + offline(60)
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true
	gui.Parent = config.parent
	refs.gui = gui

	refs.backdrop = Instance.new("Frame")
	refs.backdrop.Size = UDim2.fromScale(1, 1)
	refs.backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	refs.backdrop.BackgroundTransparency = 0.5 -- przyciemnienie (z blurem tla = fokus na itemie)
	refs.backdrop.Visible = false
	refs.backdrop.Parent = gui

	-- Spinning window (mask)
	refs.window = Instance.new("Frame")
	refs.window.Name = "Window"
	refs.window.AnchorPoint = Vector2.new(0.5, 0.5)
	refs.window.Position = UDim2.fromScale(0.5, 0.44)
	refs.window.Size = UDim2.new(0, 300, 0.72, 0) -- PIONOWY reel: waski + wysoki
	refs.window.BackgroundColor3 = Color3.fromRGB(12, 13, 18)
	refs.window.BackgroundTransparency = 1 -- BEZ RAMKI (itemy plyna po rozmytym tle, nie w pudelku)
	refs.window.ClipsDescendants = true
	refs.window.Visible = false
	refs.window.Parent = refs.backdrop
	local wCorner = Instance.new("UICorner")
	wCorner.CornerRadius = UDim.new(0, 14)
	wCorner.Parent = refs.window

	refs.strip = Instance.new("Frame")
	refs.strip.Name = "Strip"
	refs.strip.BackgroundTransparency = 1
	refs.strip.Position = UDim2.fromOffset(0, 0)
	refs.strip.Size = UDim2.new(1, 0, 0, 0) -- pelna szerokosc, rosnie w dol
	refs.strip.ZIndex = 1
	refs.strip.Parent = refs.window
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical -- PIONOWO
	layout.Padding = UDim.new(0, CARD_PADDING)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = refs.strip

	-- Edge fade: opaque at the two sides, clear in the middle, so cards dissolve
	-- into the frame instead of hard-popping at the borders.
	local fade = Instance.new("Frame")
	fade.Name = "EdgeFade"
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = refs.window.BackgroundColor3
	fade.BorderSizePixel = 0
	fade.ZIndex = 4
	fade.Parent = refs.window
	local fadeGrad = Instance.new("UIGradient")
	fadeGrad.Rotation = 90 -- pionowe wygaszanie (gora/dol)
	fadeGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.14, 1),
		NumberSequenceKeypoint.new(0.86, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	fadeGrad.Parent = fade

	-- Center marker line (above the fade)
	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.new(0, 3, 1, -8)
	marker.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	marker.BackgroundTransparency = 1 -- ukryta linia srodka (wzor: brak ramek/wskaznika)
	marker.ZIndex = 5
	marker.Parent = refs.window
	local mCorner = Instance.new("UICorner")
	mCorner.CornerRadius = UDim.new(1, 0)
	mCorner.Parent = marker

	-- Wskazniki linii losowania: podswietlone strzalki/"lzy" po lewej i prawej srodka reela (na wierzchu)
	for _, side in ipairs({ { "L", "▶", -1 }, { "R", "◀", 1 } }) do
		local ind = Instance.new("TextLabel")
		ind.Name = "Ind" .. side[1]
		ind.AnchorPoint = Vector2.new(0.5, 0.5)
		ind.Position = UDim2.new(0.5, side[3] * 170, 0.44, 0)
		ind.Size = UDim2.fromOffset(48, 64)
		ind.BackgroundTransparency = 1
		ind.Font = Enum.Font.GothamBlack; ind.Text = side[2]; ind.TextScaled = true
		ind.TextColor3 = Color3.fromRGB(255, 255, 255); ind.TextTransparency = 0.12
		ind.ZIndex = 6; ind.Parent = refs.backdrop
		local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(120, 190, 255); st.Thickness = 2.5; st.Transparency = 0.15; st.Parent = ind
	end

	-- Reveal
	refs.reveal = Instance.new("Frame")
	refs.reveal.Name = "Reveal"
	refs.reveal.Size = UDim2.fromScale(1, 1)
	refs.reveal.BackgroundTransparency = 1
	refs.reveal.Visible = false
	refs.reveal.Parent = refs.backdrop

	refs.revealInner = Instance.new("Frame")
	refs.revealInner.Name = "Inner"
	refs.revealInner.AnchorPoint = Vector2.new(0.5, 0.5)
	refs.revealInner.Position = UDim2.fromScale(0.5, 0.45)
	refs.revealInner.Size = REVEAL_SIZE
	refs.revealInner.BackgroundTransparency = 1
	refs.revealInner.Parent = refs.reveal

	refs.revealAura = Instance.new("ImageLabel")
	refs.revealAura.Name = "Aura"
	refs.revealAura.Image = config.starburstId or ""
	refs.revealAura.BackgroundTransparency = 1
	refs.revealAura.AnchorPoint = Vector2.new(0.5, 0.5)
	refs.revealAura.Position = UDim2.fromScale(0.5, 0.5)
	refs.revealAura.Size = UDim2.fromScale(1, 1)
	refs.revealAura.ImageTransparency = 0.25
	refs.revealAura.Parent = refs.revealInner

	refs.revealOdds = Instance.new("TextLabel")
	refs.revealOdds.Name = "Odds"
	refs.revealOdds.Text = "1 in 0"
	refs.revealOdds.BackgroundTransparency = 1
	refs.revealOdds.AnchorPoint = Vector2.new(0.5, 0.5)
	refs.revealOdds.Position = UDim2.fromScale(0.5, 0.1)
	refs.revealOdds.Size = UDim2.fromScale(0.7, 0.1)
	refs.revealOdds.Font = Enum.Font.FredokaOne
	refs.revealOdds.TextScaled = true
	refs.revealOdds.ZIndex = 3
	refs.revealOdds.Parent = refs.revealInner

	refs.revealName = Instance.new("TextLabel")
	refs.revealName.Name = "ItemName"
	refs.revealName.Text = ""
	refs.revealName.BackgroundTransparency = 1
	refs.revealName.AnchorPoint = Vector2.new(0.5, 0.5)
	refs.revealName.Position = UDim2.fromScale(0.5, 0.84)
	refs.revealName.Size = UDim2.fromScale(0.92, 0.09)
	refs.revealName.Font = Enum.Font.GothamBold
	refs.revealName.TextScaled = true
	refs.revealName.TextColor3 = Color3.fromRGB(255, 255, 255)
	refs.revealName.ZIndex = 3
	refs.revealName.Parent = refs.revealInner

	-- holder kaskady mnoznika (koniczyny) — nad itemem, na warstwie reveala (nie skaluje sie z itemem)
	refs.cascadeHolder = Instance.new("Frame")
	refs.cascadeHolder.Name = "Cascade"
	refs.cascadeHolder.AnchorPoint = Vector2.new(0.5, 0.5); refs.cascadeHolder.Position = UDim2.fromScale(0.5, 0.2)
	refs.cascadeHolder.Size = UDim2.fromScale(0.95, 0.16); refs.cascadeHolder.BackgroundTransparency = 1
	refs.cascadeHolder.ZIndex = 5; refs.cascadeHolder.Parent = refs.reveal

	-- Pasek sterowania — na BACKDROPIE, wiec widoczny CALY CZAS rolowania (spin + reveal): Auto | Rolka | Zamknij
	local bar = Instance.new("Frame")
	bar.Name = "RollBar"; bar.AnchorPoint = Vector2.new(0.5, 1); bar.Position = UDim2.new(0.5, 0, 1, -16)
	bar.Size = UDim2.fromOffset(440, 96); bar.BackgroundTransparency = 1; bar.ZIndex = 6; bar.Parent = refs.backdrop

	local function barBtn(name, xScale, w, h, bg, fg, txt, ts)
		local b = Instance.new("TextButton")
		b.Name = name; b.AnchorPoint = Vector2.new(0.5, 0.5); b.Position = UDim2.fromScale(xScale, 0.5)
		b.Size = UDim2.fromOffset(w, h); b.BackgroundColor3 = bg; b.TextColor3 = fg
		b.Font = Enum.Font.GothamBold; b.TextSize = ts; b.Text = txt; b.ZIndex = 7; b.Parent = bar
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = b
		return b
	end

	-- Auto (lewo) — automatyczne toczenie WŁ/WYŁ
	refs.autoBtn = barBtn("Auto", 0.15, 100, 72, Color3.fromRGB(38, 42, 52), Color3.fromRGB(150, 150, 150), "↻\nAuto: WYŁ", 13)
	refs.autoBtn.Activated:Connect(function()
		state.auto = not state.auto
		refs.autoBtn.Text = state.auto and "↻\nAuto: WŁ" or "↻\nAuto: WYŁ"
		refs.autoBtn.TextColor3 = state.auto and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(150, 150, 150)
		if state.auto and not state.rolling and cfg.onRollAgain then cfg.onRollAgain() end
	end)

	-- Rolka (srodek) — rzuc ponownie
	local rollaBtn = barBtn("Rolka", 0.5, 116, 88, Color3.fromRGB(240, 240, 240), Color3.fromRGB(30, 30, 30), "🎲\nRolka", 20)
	rollaBtn.Activated:Connect(function()
		if not state.rolling and cfg.onRollAgain then cfg.onRollAgain() end
	end)

	-- Zamknij (prawo) — wyjdz z trybu rolowania
	local closeBtn = barBtn("Zamknij", 0.85, 96, 72, Color3.fromRGB(35, 38, 48), Color3.fromRGB(255, 255, 255), "✖\nZamknij", 15)
	closeBtn.Activated:Connect(function()
		state.auto = false
		RollReelReveal.close()
	end)
end

-- result: your RollResult payload. Reads result.unitId and result.rarityN (with a
-- couple of fallbacks). Decoys are cosmetic and picked freely from the pool.
function RollReelReveal.play(result)
	if state.rolling then
		return
	end

	local unitId = result.unitId or result.id
	local unitModel = resolveModel(unitId)
	if not unitModel then
		warn("[RollReelReveal] no model for id: " .. tostring(unitId))
		return
	end
	local rarityN = result.rarityN or result.rarity or 1
	local displayName = result.name or unitModel.Name
	local tier = cfg.resolveTier(rarityN)

	state.rolling = true
	if state.wobble then
		state.wobble:Stop()
		state.wobble = nil
	end

	refs.backdrop.Visible = true
	setRevealBlur(true) -- rozmyj swiat 3D (tlo), item (GUI) zostaje ostry
	refs.reveal.Visible = false
	refs.window.Visible = true
	clearStrip()

	-- Decoy id pool: explicit cfg.decoyIds, else the names of unitsFolder children.
	local decoyIds = cfg.decoyIds
	if not decoyIds then
		decoyIds = {}
		if cfg.unitsFolder then
			for _, child in cfg.unitsFolder:GetChildren() do
				table.insert(decoyIds, child.Name)
			end
		end
	end

	-- Build the strip: kazda karta = model + aura/nazwa/"1 in N" wg WLASNEJ rzadkosci (jak qwer).
	for i = 1, TUNING.cardCount do
		local uid, model, isWinner
		if i == TUNING.winnerIndex then
			uid, model, isWinner = unitId, unitModel, true
		else
			uid = decoyIds[math.random(1, #decoyIds)]
			model, isWinner = resolveModel(uid), false
		end
		if model then
			local u = GameConfig.Units[uid]
			local rN = u and u.rarityN
			local nm = (u and u.displayName) or uid
			local col = (rN and cfg.resolveTier) and cfg.resolveTier(rN).color or NEUTRAL
			local card = makeCard(model, col, rN, nm)
			if isWinner then
				local s = Instance.new("UIScale")
				s.Parent = card
				state.winnerScale = s
			end
			card.Parent = refs.strip
		end
	end

	-- Let the layout settle one frame so AbsoluteSize is valid, then spin (one tween).
	task.wait()
	RollReel.play({
		strip = refs.strip,
		cardWidth = TUNING.cardWidth, -- pitch (wysokosc rozstawu w pionie)
		winnerIndex = TUNING.winnerIndex,
		windowWidth = refs.window.AbsoluteSize.Y, -- dlugosc okna w pionie
		duration = TUNING.duration,
		easingStyle = TUNING.easingStyle,
		jitter = TUNING.jitter,
		vertical = true,
	})

	-- Land "clunk": a scale pop on the winner card (separate property, no scroll seam).
	if state.winnerScale then
		TweenService:Create(
			state.winnerScale,
			TweenInfo.new(TUNING.landPopTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = TUNING.landPopScale }
		):Play()
		task.wait(TUNING.landPopTime)
	end

	refs.window.Visible = false
	showReveal(unitModel, rarityN, tier, displayName, result.mutation and result.mutation.mult)
	state.rolling = false

	-- automatyczne toczenie: po revealu rzuc znowu (dopoki WŁ)
	if state.auto and cfg.onRollAgain then
		task.delay(0.9, function()
			if state.auto and not state.rolling and refs.reveal.Visible then
				cfg.onRollAgain()
			end
		end)
	end
end

-- Call to dismiss the reveal (e.g. from your "Zamknij" button).
function RollReelReveal.close()
	if state.wobble then
		state.wobble:Stop()
		state.wobble = nil
	end
	setRevealBlur(false) -- zdejmij rozmycie tla
	refs.reveal.Visible = false
	refs.backdrop.Visible = false
end

return RollReelReveal
