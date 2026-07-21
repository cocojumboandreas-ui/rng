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

local RollReelReveal = {}

-- ---- tuning (all the "feel" knobs live here) --------------------------------
local TUNING = {
	cardWidth = 148, -- pitch: 132 card + 16 padding
	cardCount = 34, -- cards per spin (decoys + winner). Fewer = cheaper. Icons let you go higher.
	winnerIndex = 30, -- where the real winner sits (leave a few cards after it)
	duration = 4.6, -- spin seconds
	easingStyle = Enum.EasingStyle.Quint, -- Quint/Quart Out = long fast run, clean settle
	jitter = 26, -- +/- px off dead-center for a natural stop (keep small)
	landPopScale = 1.14, -- winner card scale pop on land
	landPopTime = 0.16,
}
local CARD_PADDING = 16
local NEUTRAL = Color3.fromRGB(70, 74, 84)
local REVEAL_SIZE = UDim2.fromOffset(480, 560)
local REVEAL_SIZE_SMALL = UDim2.fromOffset(48, 56)

local cfg = {}
local refs = {}
local state = { rolling = false, wobble = nil, winnerScale = nil }

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

local function makeCard(model: Instance, strokeColor: Color3): Frame
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(TUNING.cardWidth - CARD_PADDING, 168)
	card.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
	card.BackgroundTransparency = 0.08

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = card

	if cfg.iconFor then
		-- Cheap, buttery reel: 2D icons scroll without per-frame GPU cost.
		local icon = Instance.new("ImageLabel")
		icon.Image = cfg.iconFor(model.Name)
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(0.85, 0.85)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = card
	else
		local vpf = buildViewport(model, card)
		vpf.AnchorPoint = Vector2.new(0.5, 0.5)
		vpf.Position = UDim2.fromScale(0.5, 0.5)
		vpf.Size = UDim2.fromScale(0.9, 0.9)
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

local function showReveal(model: Instance, rarityN: number, tier, displayName: string)
	refs.reveal.Visible = true
	refs.revealAura.ImageColor3 = tier.color
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
	task.delay(0.35, function()
		if state.wobble then
			state.wobble:Stop()
		end
		state.wobble = Wobble.start(refs.revealInner, { rotationAmplitude = 4, bobAmplitude = 8, easeIn = 0.45 })
	end)
end

-- ---- public API -------------------------------------------------------------

function RollReelReveal.init(config)
	cfg = config

	local gui = Instance.new("ScreenGui")
	gui.Name = "RollReelReveal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true
	gui.Parent = config.parent
	refs.gui = gui

	refs.backdrop = Instance.new("Frame")
	refs.backdrop.Size = UDim2.fromScale(1, 1)
	refs.backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	refs.backdrop.BackgroundTransparency = 0.35
	refs.backdrop.Visible = false
	refs.backdrop.Parent = gui

	-- Spinning window (mask)
	refs.window = Instance.new("Frame")
	refs.window.Name = "Window"
	refs.window.AnchorPoint = Vector2.new(0.5, 0.5)
	refs.window.Position = UDim2.fromScale(0.5, 0.42)
	refs.window.Size = UDim2.new(0.9, 0, 0, 200)
	refs.window.BackgroundColor3 = Color3.fromRGB(12, 13, 18)
	refs.window.BackgroundTransparency = 0.2
	refs.window.ClipsDescendants = true
	refs.window.Visible = false
	refs.window.Parent = refs.backdrop
	local wCorner = Instance.new("UICorner")
	wCorner.CornerRadius = UDim.new(0, 14)
	wCorner.Parent = refs.window

	refs.strip = Instance.new("Frame")
	refs.strip.Name = "Strip"
	refs.strip.BackgroundTransparency = 1
	refs.strip.Position = UDim2.fromOffset(0, 16)
	refs.strip.Size = UDim2.new(0, 0, 1, -32)
	refs.strip.ZIndex = 1
	refs.strip.Parent = refs.window
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, CARD_PADDING)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
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
	marker.BackgroundTransparency = 0.2
	marker.ZIndex = 5
	marker.Parent = refs.window
	local mCorner = Instance.new("UICorner")
	mCorner.CornerRadius = UDim.new(1, 0)
	mCorner.Parent = marker

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

	-- "Zamknij" — widoczny razem z rewealem (parent do refs.reveal)
	refs.closeBtn = Instance.new("TextButton")
	refs.closeBtn.Name = "Zamknij"
	refs.closeBtn.AnchorPoint = Vector2.new(0.5, 1)
	refs.closeBtn.Position = UDim2.fromScale(0.5, 0.94)
	refs.closeBtn.Size = UDim2.fromOffset(180, 48)
	refs.closeBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
	refs.closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	refs.closeBtn.Font = Enum.Font.GothamBold
	refs.closeBtn.TextSize = 20
	refs.closeBtn.Text = "Zamknij"
	refs.closeBtn.ZIndex = 6
	refs.closeBtn.Parent = refs.reveal
	local cbCorner = Instance.new("UICorner")
	cbCorner.CornerRadius = UDim.new(0, 10)
	cbCorner.Parent = refs.closeBtn
	refs.closeBtn.Activated:Connect(function()
		RollReelReveal.close()
	end)

	-- Tap na tło (poza spinem) też zamyka reveal.
	refs.backdrop.Active = true
	refs.backdrop.InputBegan:Connect(function(input)
		if state.rolling or not refs.reveal.Visible then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			RollReelReveal.close()
		end
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

	-- Build the strip: cosmetic decoys, with the real winner at winnerIndex.
	for i = 1, TUNING.cardCount do
		local model, color, isWinner
		if i == TUNING.winnerIndex then
			model, color, isWinner = unitModel, tier.color, true
		else
			model, color, isWinner = resolveModel(decoyIds[math.random(1, #decoyIds)]), NEUTRAL, false
		end
		if model then
			local card = makeCard(model, color)
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
		cardWidth = TUNING.cardWidth,
		winnerIndex = TUNING.winnerIndex,
		windowWidth = refs.window.AbsoluteSize.X,
		duration = TUNING.duration,
		easingStyle = TUNING.easingStyle,
		jitter = TUNING.jitter,
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
	showReveal(unitModel, rarityN, tier, displayName)
	state.rolling = false
end

-- Call to dismiss the reveal (e.g. from your "Zamknij" button).
function RollReelReveal.close()
	if state.wobble then
		state.wobble:Stop()
		state.wobble = nil
	end
	refs.reveal.Visible = false
	refs.backdrop.Visible = false
end

return RollReelReveal
