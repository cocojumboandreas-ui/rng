--!nonstrict
-- RollReel: generic slot-machine reel animation.
-- Operates PURELY on GuiObjects — it knows nothing about items, units, or rarity.
-- Framework module: reusable for any "spin a horizontal strip and land on a winner" UI.
--
-- The caller builds the cards (as children of `strip`, laid out by a Horizontal
-- UIListLayout with Padding), tells RollReel which index is the winner, and RollReel
-- scrolls the strip so that card ends centered under the window. Fast -> slow easing
-- gives the one-armed-bandit feel.

local TweenService = game:GetService("TweenService")

local RollReel = {}

export type ReelConfig = {
	strip: Frame, -- Frame holding the cards; child of the visible (ClipsDescendants) window
	cardWidth: number, -- center-to-center pitch of one card in px (card width + layout padding)
	winnerIndex: number, -- 1-based index of the winning card within `strip`
	windowWidth: number, -- width of the visible window Frame (usually window.AbsoluteSize.X)
	duration: number?, -- total spin time in seconds (default 5)
	easingStyle: Enum.EasingStyle?, -- default Quint (long fast run, gentle settle)
	jitter: number?, -- +/- px random offset from dead center, for a natural stop (default 0)
}

-- Strip X offset (px) that centers a given card index under the window center.
local function offsetForIndex(index: number, cardWidth: number, windowWidth: number): number
	local cardCenter = (index - 1) * cardWidth + cardWidth / 2
	return windowWidth / 2 - cardCenter
end

-- Plays the reel. YIELDS in the calling thread until the animation finishes.
-- config.vertical = true -> przewija w PIONIE (oś Y); inaczej w poziomie (oś X).
-- cardWidth = pitch (rozstaw wzdluz osi przewijania), windowWidth = dlugosc okna wzdluz tej osi.
function RollReel.play(config: ReelConfig)
	local duration = config.duration or 5
	local easingStyle = config.easingStyle or Enum.EasingStyle.Quint
	local jitter = config.jitter or 0
	local strip = config.strip
	local vertical = config.vertical

	-- reset pozycji na osi przewijania do 0 (druga os bez zmian)
	if vertical then
		strip.Position = UDim2.new(strip.Position.X.Scale, strip.Position.X.Offset, 0, 0)
	else
		strip.Position = UDim2.new(0, 0, strip.Position.Y.Scale, strip.Position.Y.Offset)
	end

	local targetOffset = offsetForIndex(config.winnerIndex, config.cardWidth, config.windowWidth)
	if jitter > 0 then
		targetOffset += math.random(-jitter, jitter)
	end

	local goal
	if vertical then
		goal = UDim2.new(strip.Position.X.Scale, strip.Position.X.Offset, 0, targetOffset)
	else
		goal = UDim2.new(0, targetOffset, strip.Position.Y.Scale, strip.Position.Y.Offset)
	end

	local info = TweenInfo.new(duration, easingStyle, Enum.EasingDirection.Out)
	local tween = TweenService:Create(strip, info, { Position = goal })
	tween:Play()
	tween.Completed:Wait()
end

return RollReel
