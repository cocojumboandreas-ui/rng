--!strict
-- Framework/UI/Haptic.luau
-- RNG has no haptic layer yet. Minimal port: same GetShared/Play shape as the source system's
-- HapticClass so ButtonUI doesn't need special-casing, but the implementation is a safe no-op
-- wrapper around HapticService (only fires if a supported gamepad motor is actually present).

local HapticService = game:GetService("HapticService")

local Haptic = {}
Haptic.__index = Haptic

local shared: { [string]: any } = {}

function Haptic.GetShared(name: string, effectType: Enum.HapticEffectType)
	local existing = shared[name]
	if existing then
		return existing
	end

	local self = setmetatable({ EffectType = effectType }, Haptic)
	shared[name] = self
	return self
end

function Haptic:Play()
	pcall(function()
		if not HapticService:IsVibrationSupported(Enum.UserInputType.Gamepad1) then
			return
		end
		HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0.4)
	end)
end

return Haptic
