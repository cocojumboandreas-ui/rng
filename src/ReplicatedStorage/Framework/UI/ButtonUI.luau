--!strict
-- Framework/UI/ButtonUI.luau
-- Ported from the reference place's Client/UI/Universal/ButtonUI (Phase B UI port, Step 2).
-- Feel layer only: hover / press / release / idle tweens on scale, rotation, gradient offset,
-- stroke thickness, shadow/glow, plus click sound + optional haptic. Touch-vs-mouse handling is
-- unchanged from the source. Tag "IsAButton" is wired by the Step 4 tag dispatcher
-- (WR_UITagDispatcher), which calls New()/Destroy() automatically.
local ReplicatedStorage = game:GetService(`ReplicatedStorage`)
local TweenService = game:GetService(`TweenService`)
local UserInputService = game:GetService(`UserInputService`)

local Maid = require(ReplicatedStorage.Framework.Maid)
local HapticClass = require(ReplicatedStorage.Framework.UI.Haptic)
local PlaySfx = require(ReplicatedStorage.Framework.UI.PlaySfx)

local ButtonUI = {}
ButtonUI.__index = ButtonUI
ButtonUI.Type = `Tag`
ButtonUI.Tag = `IsAButton`
ButtonUI.Index = 99

export type Self = typeof(ButtonUI) & {
	Button: GuiButton,
	Maid: Maid.Maid,
	Scale: UIScale,
	EffectsHolder: Frame,
	MovableObjects: { GuiObject },
	BasePositions: { [GuiObject]: UDim2 },
	Gradients: { UIGradient },
	GradientOffsets: { [UIGradient]: Vector2 },
	Strokes: { UIStroke },
	StrokeThickness: { [UIStroke]: number },
	Shadow: ImageLabel?,
	Glow: ImageLabel?,
	BaseShadowTransparency: number?,
	BaseGlowTransparency: number?,
	BaseButtonRotation: number,
	BaseAutoButtonColor: boolean,
	HoverRotation: number,
	IsHovering: boolean,
	IsPressed: boolean,
	AnimationId: number,
	Tweens: { Tween },
	LastPressFeedbackAt: number,
	CreatedScale: boolean,
	CreatedEffectsHolder: boolean,
	ClickHaptic: any,
	HoverHaptic: any,
}

local ClickHaptic = HapticClass.GetShared(`ui-click`, Enum.HapticEffectType.UIClick)
local HoverHaptic = HapticClass.GetShared(`ui-hover`, Enum.HapticEffectType.UIHover)

local IDLE_TIME = 0.16
local HOVER_TIME = 0.22
local PRESS_TIME = 0.08
local RELEASE_POP_TIME = 0.1
local RELEASE_SETTLE_TIME = 0.14

local IDLE_INFO = TweenInfo.new(IDLE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local HOVER_INFO = TweenInfo.new(HOVER_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(PRESS_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_POP_INFO = TweenInfo.new(RELEASE_POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local RELEASE_SETTLE_INFO = TweenInfo.new(RELEASE_SETTLE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local HOVER_SCALE = 1.06
local PRESS_SCALE = 0.94
local RELEASE_SCALE = 1.1

local HOVER_OFFSET_Y = -3
local PRESS_OFFSET_Y = 2
local RELEASE_OFFSET_Y = -4

local HOVER_STROKE_BOOST = 0.35
local PRESS_STROKE_BOOST = 0.2
local RELEASE_STROKE_BOOST = 0.5

local HOVER_SHADOW_DELTA = -0.08
local PRESS_SHADOW_DELTA = 0.08
local RELEASE_SHADOW_DELTA = -0.1

local HOVER_GLOW_DELTA = -0.18
local PRESS_GLOW_DELTA = -0.05
local RELEASE_GLOW_DELTA = -0.2

local ZERO_VECTOR2 = Vector2.new()

local HOVER_GRADIENT_OFFSET = Vector2.new(0, -0.04)
local PRESS_GRADIENT_OFFSET = Vector2.new(0, 0.05)
local RELEASE_GRADIENT_OFFSET = Vector2.new(0, -0.06)
local EXCLUDED_MOVABLE_NAMES = {
	ButtonUIScale = true,
	ButtonUIEffects = true,
	Shadow = true,
	Glow = true,
}

local FEEDBACK_DEDUPE_WINDOW = 0.08

function ButtonUI.New(Button: GuiButton)
	local self = setmetatable({}, ButtonUI) :: Self
	self.Button = Button
	self.Maid = Maid.new()
	self.MovableObjects = {}
	self.BasePositions = {}
	self.Gradients = {}
	self.GradientOffsets = {}
	self.Strokes = {}
	self.StrokeThickness = {}
	self.BaseButtonRotation = Button.Rotation
	self.BaseAutoButtonColor = Button.AutoButtonColor
	self.HoverRotation = 0
	self.IsHovering = false
	self.IsPressed = false
	self.AnimationId = 0
	self.Tweens = {}
	self.LastPressFeedbackAt = -math.huge
	self.CreatedScale = false
	self.CreatedEffectsHolder = false

	self.ClickHaptic = ClickHaptic
	self.HoverHaptic = HoverHaptic

	self:_CreateScale()
	self:_CreateEffectsHolder()
	self:_CollectMovableObjects()
	self:_CollectStrokes()
	self:_CollectGradients()
	self:_CollectDecorations()
	self.HoverRotation = self:_ResolveHoverRotation()

	self.Button.AutoButtonColor = false

	self:_SetState(1, 0, 0, ZERO_VECTOR2, 0, 0, 0)
	self:_Connect()

	return self
end

function ButtonUI:_PlayHoverSound()
	if self.Button:GetAttribute(`DisableHoverSound`) == true then
		return
	end

	PlaySfx(`Pop8`)
end

function ButtonUI:_PlayPressFeedback()
	local Now = os.clock()
	if Now - self.LastPressFeedbackAt < FEEDBACK_DEDUPE_WINDOW then
		return
	end

	self.LastPressFeedbackAt = Now
	self:_PlayClickSound()
	self:_PlayRipple()
end

function ButtonUI:_PlayClickSound()
	if self.Button:GetAttribute(`DisableClickSound`) == true then
		return
	end

	PlaySfx(`Pop6`)
end

function ButtonUI:_IsTouchInput(): boolean
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

function ButtonUI:_ShouldHandleActivated(): boolean
	return self:_IsTouchInput() or not UserInputService.MouseEnabled
end

function ButtonUI._Connect(self: Self)
	self.Maid:GiveTask(self.Button.MouseEnter:Connect(function()
		self.IsHovering = true
		if self.IsPressed then
			return
		end

		self:_PlayHoverSound()
		self:_AnimateHover()
	end))

	self.Maid:GiveTask(self.Button.MouseLeave:Connect(function()
		self.IsHovering = false
		self.IsPressed = false
		self:_AnimateIdle()
	end))

	self.Maid:GiveTask(self.Button.MouseButton1Down:Connect(function()
		self.IsPressed = true
		if self:_IsTouchInput() then
			self:_AnimatePress()
			return
		end

		self:_PlayPressFeedback()
		self:_AnimatePress()
	end))

	self.Maid:GiveTask(self.Button.MouseButton1Up:Connect(function()
		if self:_IsTouchInput() or not self.IsPressed then
			return
		end

		self.IsPressed = false
		self:_AnimateRelease()
	end))

	self.Maid:GiveTask(self.Button.Activated:Connect(function()
		if not self:_ShouldHandleActivated() then
			return
		end

		self:_PlayPressFeedback()
		self.IsPressed = false
		self:_AnimateRelease()
	end))

	self.Maid:GiveTask(UserInputService.InputEnded:Connect(function(Input: InputObject)
		if not self.IsPressed then
			return
		end
		if Input.UserInputType ~= Enum.UserInputType.MouseButton1 and Input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if self:_IsTouchInput() and Input.UserInputType == Enum.UserInputType.Touch then
			return
		end

		self.IsPressed = false
		if self.IsHovering then
			self:_AnimateRelease()
		else
			self:_AnimateIdle()
		end
	end))
end

function ButtonUI:_CreateScale()
	local Scale = self.Button:FindFirstChild(`ButtonUIScale`)
	if not Scale or not Scale:IsA(`UIScale`) then
		Scale = Instance.new(`UIScale`)
		Scale.Name = `ButtonUIScale`
		Scale.Parent = self.Button
		self.CreatedScale = true
	end

	self.Scale = Scale :: UIScale
	if self.CreatedScale then
		self.Maid:GiveTask(self.Scale)
	end
end

function ButtonUI:_CreateEffectsHolder()
	local EffectsHolder = self.Button:FindFirstChild(`ButtonUIEffects`)
	if not EffectsHolder or not EffectsHolder:IsA(`Frame`) then
		EffectsHolder = Instance.new(`Frame`)
		EffectsHolder.Name = `ButtonUIEffects`
		EffectsHolder.AnchorPoint = Vector2.new(0.5, 0.5)
		EffectsHolder.Position = UDim2.fromScale(0.5, 0.5)
		EffectsHolder.Size = UDim2.fromScale(1, 1)
		EffectsHolder.BackgroundTransparency = 1
		EffectsHolder.BorderSizePixel = 0
		EffectsHolder.Active = false
		EffectsHolder.ZIndex = self.Button.ZIndex + 20
		EffectsHolder.ClipsDescendants = true
		EffectsHolder.Parent = self.Button
		self.CreatedEffectsHolder = true
	end

	self.EffectsHolder = EffectsHolder :: Frame
	self:_ApplyEffectsCorner()

	if self.CreatedEffectsHolder then
		self.Maid:GiveTask(self.EffectsHolder)
	end
end

function ButtonUI:_ApplyEffectsCorner()
	for _, Child in ipairs(self.EffectsHolder:GetChildren()) do
		if Child:IsA(`UICorner`) then
			Child:Destroy()
		end
	end

	local CornerSource = self:_FindFirstDescendantOfClass(self.Button, `UICorner`)
	if not CornerSource or not CornerSource:IsA(`UICorner`) then
		return
	end

	local Corner = CornerSource:Clone()
	Corner.Parent = self.EffectsHolder
end

function ButtonUI:_CollectMovableObjects()
	for _, Child in ipairs(self.Button:GetChildren()) do
		if not Child:IsA(`GuiObject`) then
			continue
		end
		if EXCLUDED_MOVABLE_NAMES[Child.Name] then
			continue
		end

		table.insert(self.MovableObjects, Child)
		self.BasePositions[Child] = Child.Position
	end
end

function ButtonUI:_CollectStrokes()
	for _, Descendant in ipairs(self.Button:GetDescendants()) do
		if not Descendant:IsA(`UIStroke`) then
			continue
		end

		table.insert(self.Strokes, Descendant)
		self.StrokeThickness[Descendant] = Descendant.Thickness
	end
end

function ButtonUI:_CollectGradients()
	for _, Descendant in ipairs(self.Button:GetDescendants()) do
		if not Descendant:IsA(`UIGradient`) then
			continue
		end

		table.insert(self.Gradients, Descendant)
		self.GradientOffsets[Descendant] = Descendant.Offset
	end
end

function ButtonUI:_CollectDecorations()
	local Shadow = self.Button:FindFirstChild(`Shadow`, true)
	if Shadow and Shadow:IsA(`ImageLabel`) then
		self.Shadow = Shadow
		self.BaseShadowTransparency = Shadow.ImageTransparency
	end

	local Glow = self.Button:FindFirstChild(`Glow`, true)
	if Glow and Glow:IsA(`ImageLabel`) then
		self.Glow = Glow
		self.BaseGlowTransparency = Glow.ImageTransparency
	end
end

function ButtonUI:_ResolveHoverRotation(): number
	local Hash = 0
	for Index = 1, #self.Button.Name do
		Hash += string.byte(self.Button.Name, Index)
	end

	return (Hash % 2 == 0 and 1 or -1) * 1.6
end

function ButtonUI:_GetNextAnimationId(): number
	self.AnimationId += 1
	return self.AnimationId
end

function ButtonUI:_AnimateIdle()
	self:_GetNextAnimationId()
	self:_AnimateState(IDLE_INFO, 1, 0, 0, ZERO_VECTOR2, 0, 0, 0)
end

function ButtonUI:_AnimateHover()
	self:_GetNextAnimationId()
	self:_AnimateState(HOVER_INFO, HOVER_SCALE, self.HoverRotation, HOVER_OFFSET_Y, HOVER_GRADIENT_OFFSET, HOVER_STROKE_BOOST, HOVER_SHADOW_DELTA, HOVER_GLOW_DELTA)
end

function ButtonUI:_AnimatePress()
	self:_GetNextAnimationId()
	self:_AnimateState(PRESS_INFO, PRESS_SCALE, 0, PRESS_OFFSET_Y, PRESS_GRADIENT_OFFSET, PRESS_STROKE_BOOST, PRESS_SHADOW_DELTA, PRESS_GLOW_DELTA)
end

function ButtonUI:_AnimateRelease()
	local AnimationId = self:_GetNextAnimationId()
	self:_AnimateState(RELEASE_POP_INFO, RELEASE_SCALE, self.HoverRotation, RELEASE_OFFSET_Y, RELEASE_GRADIENT_OFFSET, RELEASE_STROKE_BOOST, RELEASE_SHADOW_DELTA, RELEASE_GLOW_DELTA)

	task.delay(RELEASE_POP_TIME, function()
		if self.AnimationId ~= AnimationId then
			return
		end
		if not self.Button.Parent then
			return
		end
		if self.IsPressed then
			return
		end

		if self.IsHovering then
			self:_AnimateState(RELEASE_SETTLE_INFO, HOVER_SCALE, self.HoverRotation, HOVER_OFFSET_Y, HOVER_GRADIENT_OFFSET, HOVER_STROKE_BOOST, HOVER_SHADOW_DELTA, HOVER_GLOW_DELTA)
		else
			self:_AnimateState(RELEASE_SETTLE_INFO, 1, 0, 0, ZERO_VECTOR2, 0, 0, 0)
		end
	end)
end

function ButtonUI:_AnimateState(TweenInfo: TweenInfo, ScaleValue: number, Rotation: number, YOffset: number, GradientOffset: Vector2, StrokeBoost: number, ShadowDelta: number, GlowDelta: number)
	self:_ClearTweens()

	self:_PlayTween(self.Scale, TweenInfo, {
		Scale = ScaleValue,
	})
	self:_PlayTween(self.Button, TweenInfo, {
		Rotation = self.BaseButtonRotation + Rotation,
	})

	for _, Object in ipairs(self.MovableObjects) do
		local BasePosition = self.BasePositions[Object]
		if not BasePosition then
			continue
		end

		self:_PlayTween(Object, TweenInfo, {
			Position = self:_OffsetUDim2(BasePosition, 0, YOffset),
		})
	end

	for _, Gradient in ipairs(self.Gradients) do
		local BaseOffset = self.GradientOffsets[Gradient]
		if not BaseOffset then
			continue
		end

		self:_PlayTween(Gradient, TweenInfo, {
			Offset = self:_OffsetVector2(BaseOffset, GradientOffset.X, GradientOffset.Y),
		})
	end

	for _, Stroke in ipairs(self.Strokes) do
		local BaseThickness = self.StrokeThickness[Stroke]
		if not BaseThickness then
			continue
		end

		self:_PlayTween(Stroke, TweenInfo, {
			Thickness = BaseThickness + StrokeBoost,
		})
	end

	if self.Shadow and self.BaseShadowTransparency then
		self:_PlayTween(self.Shadow, TweenInfo, {
			ImageTransparency = math.clamp(self.BaseShadowTransparency + ShadowDelta, 0, 1),
		})
	end
	if self.Glow and self.BaseGlowTransparency then
		self:_PlayTween(self.Glow, TweenInfo, {
			ImageTransparency = math.clamp(self.BaseGlowTransparency + GlowDelta, 0, 1),
		})
	end
end

function ButtonUI:_SetState(ScaleValue: number, Rotation: number, YOffset: number, GradientOffset: Vector2, StrokeBoost: number, ShadowDelta: number, GlowDelta: number)
	self.Scale.Scale = ScaleValue
	self.Button.Rotation = self.BaseButtonRotation + Rotation

	for _, Object in ipairs(self.MovableObjects) do
		local BasePosition = self.BasePositions[Object]
		if not BasePosition then
			continue
		end

		Object.Position = self:_OffsetUDim2(BasePosition, 0, YOffset)
	end

	for _, Gradient in ipairs(self.Gradients) do
		local BaseOffset = self.GradientOffsets[Gradient]
		if not BaseOffset then
			continue
		end

		Gradient.Offset = self:_OffsetVector2(BaseOffset, GradientOffset.X, GradientOffset.Y)
	end

	for _, Stroke in ipairs(self.Strokes) do
		local BaseThickness = self.StrokeThickness[Stroke]
		if not BaseThickness then
			continue
		end

		Stroke.Thickness = BaseThickness + StrokeBoost
	end

	if self.Shadow and self.BaseShadowTransparency then
		self.Shadow.ImageTransparency = math.clamp(self.BaseShadowTransparency + ShadowDelta, 0, 1)
	end
	if self.Glow and self.BaseGlowTransparency then
		self.Glow.ImageTransparency = math.clamp(self.BaseGlowTransparency + GlowDelta, 0, 1)
	end
end

function ButtonUI:_PlayTween(Target: Instance, TweenInfo: TweenInfo, Goal: { [string]: any })
	if not next(Goal) then
		return
	end

	local Tween = TweenService:Create(Target, TweenInfo, Goal)
	table.insert(self.Tweens, Tween)
	Tween:Play()
end

function ButtonUI:_ClearTweens()
	for _, Tween in ipairs(self.Tweens) do
		Tween:Cancel()
	end

	table.clear(self.Tweens)
end

function ButtonUI:_PlayRipple()
	if not self.EffectsHolder or not self.EffectsHolder.Parent then
		return
	end

	local Ripple = Instance.new(`Frame`)
	Ripple.Name = `Ripple`
	Ripple.AnchorPoint = Vector2.new(0.5, 0.5)
	Ripple.Position = UDim2.fromScale(0.5, 0.5)
	Ripple.Size = UDim2.fromOffset(0, 0)
	Ripple.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Ripple.BackgroundTransparency = 0.72
	Ripple.BorderSizePixel = 0
	Ripple.Active = false
	Ripple.ZIndex = self.EffectsHolder.ZIndex + 1
	Ripple.Parent = self.EffectsHolder

	local Corner = Instance.new(`UICorner`)
	Corner.CornerRadius = UDim.new(1, 0)
	Corner.Parent = Ripple

	local MaxSize = math.max(self.Button.AbsoluteSize.X, self.Button.AbsoluteSize.Y, 60) * 1.35
	local RippleTween = TweenService:Create(Ripple, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(MaxSize, MaxSize),
		BackgroundTransparency = 1,
	})
	RippleTween:Play()
	RippleTween.Completed:Once(function()
		Ripple:Destroy()
	end)
end

function ButtonUI:_OffsetUDim2(Value: UDim2, XOffset: number, YOffset: number): UDim2
	return UDim2.new(Value.X.Scale, Value.X.Offset + XOffset, Value.Y.Scale, Value.Y.Offset + YOffset)
end

function ButtonUI:_OffsetVector2(Value: Vector2, XOffset: number, YOffset: number): Vector2
	return Vector2.new(Value.X + XOffset, Value.Y + YOffset)
end

function ButtonUI:_FindFirstDescendantOfClass(Root: Instance, ClassName: string): Instance?
	for _, Descendant in ipairs(Root:GetDescendants()) do
		if Descendant.ClassName == ClassName then
			return Descendant
		end
	end

	return nil
end

function ButtonUI.Destroy(self: Self)
	self:_ClearTweens()
	self:_SetState(1, 0, 0, ZERO_VECTOR2, 0, 0, 0)

	if self.Button then
		self.Button.AutoButtonColor = self.BaseAutoButtonColor
		self.Button.Rotation = self.BaseButtonRotation
	end

	if self.Maid then
		self.Maid:DoCleaning()
	end
end

return ButtonUI
