--!nonstrict
-- Wobble: looped idle sway (gentle rotation + vertical bob) for any GuiObject.
-- Framework module. Returns a handle with :Stop() that restores the original transform.
-- Use it on the reveal container so the won item "kołysze się" on screen.

local RunService = game:GetService("RunService")

local Wobble = {}

export type WobbleConfig = {
	rotationAmplitude: number?, -- degrees of sway, default 4
	rotationSpeed: number?, -- oscillation speed, default 2
	bobAmplitude: number?, -- vertical bob in px, default 6
	bobSpeed: number?, -- bob speed, default 1.6
	easeIn: number?, -- seconds to ramp the sway up from zero, default 0.4 (no snap-on)
}

export type WobbleHandle = { Stop: (self: WobbleHandle) -> () }

function Wobble.start(target: GuiObject, config: WobbleConfig?): WobbleHandle
	local c = config or {}
	local rotAmp = c.rotationAmplitude or 4
	local rotSpeed = c.rotationSpeed or 2
	local bobAmp = c.bobAmplitude or 6
	local bobSpeed = c.bobSpeed or 1.6
	local easeIn = c.easeIn or 0.4

	local basePos = target.Position
	local baseRot = target.Rotation
	local t = 0

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		-- smoothstep ramp so the sway eases in from rest instead of starting abruptly
		local ramp = if easeIn > 0 then math.clamp(t / easeIn, 0, 1) else 1
		ramp = ramp * ramp * (3 - 2 * ramp)
		target.Rotation = baseRot + math.sin(t * rotSpeed) * rotAmp * ramp
		target.Position = basePos + UDim2.fromOffset(0, math.sin(t * bobSpeed) * bobAmp * ramp)
	end)

	local handle = {}
	function handle:Stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		target.Rotation = baseRot
		target.Position = basePos
	end
	return handle
end

return Wobble
