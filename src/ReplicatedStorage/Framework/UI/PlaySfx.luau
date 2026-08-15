--!strict
-- Framework/UI/PlaySfx.luau
-- RNG-native replacement for the source place's named-sound PlaySfx. RNG already has a shared
-- UI click AudioPlayer (SoundService.Audio.Players.Pop, routed through MainOutput) used by
-- Roll.UI.Components.BaseItem for the reel tick sound. Reused here instead of adding a new sound
-- asset. Self-contained on purpose: no dependency on anything under ReplicatedStorage.Roll.

local SoundService = game:GetService("SoundService")

local audioTarget = SoundService.Audio.MainOutput
local popSound = SoundService.Audio.Players.Pop

local function PlaySfx(_name: string)
	local player = popSound:Clone()
	player.Parent = audioTarget

	local wire = Instance.new("Wire")
	wire.SourceInstance = player
	wire.TargetInstance = audioTarget
	wire.Parent = player

	player:Play()
	player.Ended:Once(function()
		player:Destroy()
	end)
end

return PlaySfx
