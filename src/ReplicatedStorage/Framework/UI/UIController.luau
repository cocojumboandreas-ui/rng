--!strict
-- Framework/UI/UIController.luau
-- Faza B UI port, Krok 3: UIController OKROJONY. Zachowuje Register/Open/Close/Toggle i animacje
-- panelu (pop-scale + stroke boost + gradient offset). Celowo WYCIETE wzgledem zrodla: globalny
-- Lighting blur, zoom kamery (FieldOfView), hardkodowane auto-chowanie SideButtons, efekt "flash",
-- tweening transparencji zawartosci, logika Egg Hud -- wszystko specyficzne dla tamtej gry albo
-- poza zakresem tego kroku. Osobny, swiezy rejestr okien -- nie zna istniejacych paneli RNG
-- (roll/index/build maja wlasne systemy, ten modul o nich nic nie wie).

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local UIController = {}
UIController.Disabled = false :: boolean
UIController._OpenRequestToken = 0 :: number

local Window = {}
Window.__index = Window

export type Window = typeof(Window) & {
	_Instance: GuiObject,
	_Scale: UIScale,
	_AnimationId: number,
	_IsClosing: boolean,
	_Tweens: { Tween },
	_Strokes: { UIStroke },
	_BaseStrokeThickness: { [UIStroke]: number },
	_Gradients: { UIGradient },
	_BaseGradientOffsets: { [UIGradient]: Vector2 },
}

local Registered = {} :: { [string]: Window }
UIController.Registered = Registered

local WINDOW_SCALE_NAME = "WR_WindowUIScale"
local ORIGINAL_POSITION_ATTRIBUTE = "WR_WindowOriginalPosition"
local ORIGINAL_SCALE_ATTRIBUTE = "WR_WindowOriginalScale"

local OPEN_POP_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local OPEN_SETTLE_INFO = TweenInfo.new(0.11, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local SWITCH_CLOSE_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
local SWITCH_OPEN_DELAY = 0.055

local OPEN_START_SCALE = 0.93
local OPEN_POP_SCALE = 1.018
local CLOSE_END_SCALE = 0.975

local OPEN_START_OFFSET_Y = 16
local OPEN_POP_OFFSET_Y = -2
local CLOSE_END_OFFSET_Y = 8

local OPEN_START_GRADIENT_OFFSET = Vector2.new(0, 0.06)
local OPEN_POP_GRADIENT_OFFSET = Vector2.new(0, -0.04)
local CLOSE_GRADIENT_OFFSET = Vector2.new(0, 0.03)
local ZERO_VECTOR2 = Vector2.new()

local OPEN_STROKE_BOOST = 0.32
local CLOSE_STROKE_BOOST = 0.1

function Window:_CollectStrokes()
	if #self._Strokes > 0 then
		return
	end

	for _, Descendant in ipairs(self._Instance:GetDescendants()) do
		if Descendant:IsA("UIStroke") then
			table.insert(self._Strokes, Descendant)
			self._BaseStrokeThickness[Descendant] = Descendant.Thickness
		end
	end
end

function Window:_CollectGradients()
	if #self._Gradients > 0 then
		return
	end

	for _, Descendant in ipairs(self._Instance:GetDescendants()) do
		if Descendant:IsA("UIGradient") then
			table.insert(self._Gradients, Descendant)
			self._BaseGradientOffsets[Descendant] = Descendant.Offset
		end
	end
end

function Window:_EnsureAnimationData()
	local Frame = self._Instance

	if typeof(Frame:GetAttribute(ORIGINAL_POSITION_ATTRIBUTE)) ~= "UDim2" then
		Frame:SetAttribute(ORIGINAL_POSITION_ATTRIBUTE, Frame.Position)
	end

	if not self._Scale or not self._Scale.Parent then
		local Scale = Frame:FindFirstChild(WINDOW_SCALE_NAME)
		if not Scale or not Scale:IsA("UIScale") then
			Scale = Instance.new("UIScale")
			Scale.Name = WINDOW_SCALE_NAME
			Scale.Parent = Frame
		end
		self._Scale = Scale :: UIScale
	end

	if typeof(Frame:GetAttribute(ORIGINAL_SCALE_ATTRIBUTE)) ~= "number" then
		Frame:SetAttribute(ORIGINAL_SCALE_ATTRIBUTE, self._Scale.Scale)
	end

	self:_CollectStrokes()
	self:_CollectGradients()
end

function Window:_GetOriginalPosition(): UDim2
	self:_EnsureAnimationData()
	return (self._Instance:GetAttribute(ORIGINAL_POSITION_ATTRIBUTE) :: UDim2) or self._Instance.Position
end

function Window:_GetOriginalScale(): number
	self:_EnsureAnimationData()
	return (self._Instance:GetAttribute(ORIGINAL_SCALE_ATTRIBUTE) :: number) or 1
end

function Window:_GetNextAnimationId(): number
	self._AnimationId += 1
	return self._AnimationId
end

function Window:_ClearTweens()
	for _, CurrentTween in ipairs(self._Tweens) do
		CurrentTween:Cancel()
	end
	table.clear(self._Tweens)
end

function Window:_PlayTween(Target: Instance, Info: TweenInfo, Goal: { [string]: any }): Tween?
	if not next(Goal) then
		return nil
	end

	local CurrentTween = TweenService:Create(Target, Info, Goal)
	table.insert(self._Tweens, CurrentTween)
	CurrentTween:Play()
	return CurrentTween
end

function Window:_OffsetUDim2(Value: UDim2, XOffset: number, YOffset: number): UDim2
	return UDim2.new(Value.X.Scale, Value.X.Offset + XOffset, Value.Y.Scale, Value.Y.Offset + YOffset)
end

function Window:_OffsetVector2(Value: Vector2, XOffset: number, YOffset: number): Vector2
	return Vector2.new(Value.X + XOffset, Value.Y + YOffset)
end

function Window:_ApplyAccentState(GradientOffset: Vector2, StrokeBoost: number)
	for _, Gradient in ipairs(self._Gradients) do
		local BaseOffset = self._BaseGradientOffsets[Gradient]
		if not BaseOffset then
			continue
		end
		Gradient.Offset = self:_OffsetVector2(BaseOffset, GradientOffset.X, GradientOffset.Y)
	end

	for _, Stroke in ipairs(self._Strokes) do
		local BaseThickness = self._BaseStrokeThickness[Stroke]
		if not BaseThickness then
			continue
		end
		Stroke.Thickness = BaseThickness + StrokeBoost
	end
end

function Window:_TweenAccentState(Info: TweenInfo, GradientOffset: Vector2, StrokeBoost: number)
	for _, Gradient in ipairs(self._Gradients) do
		local BaseOffset = self._BaseGradientOffsets[Gradient]
		if not BaseOffset then
			continue
		end
		self:_PlayTween(Gradient, Info, {
			Offset = self:_OffsetVector2(BaseOffset, GradientOffset.X, GradientOffset.Y),
		})
	end

	for _, Stroke in ipairs(self._Strokes) do
		local BaseThickness = self._BaseStrokeThickness[Stroke]
		if not BaseThickness then
			continue
		end
		self:_PlayTween(Stroke, Info, {
			Thickness = BaseThickness + StrokeBoost,
		})
	end
end

function Window:_ResetVisualState()
	self:_ClearTweens()
	self._Scale.Scale = self:_GetOriginalScale()
	self._Instance.Position = self:_GetOriginalPosition()
	self:_ApplyAccentState(ZERO_VECTOR2, 0)
end

function Window:_SetOpeningState()
	self._Scale.Scale = self:_GetOriginalScale() * OPEN_START_SCALE
	self._Instance.Position = self:_OffsetUDim2(self:_GetOriginalPosition(), 0, OPEN_START_OFFSET_Y)
	self:_ApplyAccentState(OPEN_START_GRADIENT_OFFSET, 0)
end

function Window:_OpenAnimation()
	self:_EnsureAnimationData()
	self._IsClosing = false

	local AnimationId = self:_GetNextAnimationId()
	self:_ResetVisualState()
	self._Instance.Visible = true
	self:_SetOpeningState()

	local ScaleTween = self:_PlayTween(self._Scale :: UIScale, OPEN_POP_INFO, {
		Scale = self:_GetOriginalScale() * OPEN_POP_SCALE,
	})
	self:_PlayTween(self._Instance, OPEN_POP_INFO, {
		Position = self:_OffsetUDim2(self:_GetOriginalPosition(), 0, OPEN_POP_OFFSET_Y),
	})
	self:_TweenAccentState(OPEN_POP_INFO, OPEN_POP_GRADIENT_OFFSET, OPEN_STROKE_BOOST)

	if not ScaleTween then
		self:_ResetVisualState()
		return
	end

	ScaleTween.Completed:Once(function()
		if self._AnimationId ~= AnimationId then
			return
		end
		if not self._Instance.Parent then
			return
		end

		self:_PlayTween(self._Scale :: UIScale, OPEN_SETTLE_INFO, {
			Scale = self:_GetOriginalScale(),
		})
		self:_PlayTween(self._Instance, OPEN_SETTLE_INFO, {
			Position = self:_GetOriginalPosition(),
		})
		self:_TweenAccentState(OPEN_SETTLE_INFO, ZERO_VECTOR2, 0)
	end)
end

function Window:_CloseAnimation(CloseTweenInfo: TweenInfo?)
	self:_EnsureAnimationData()
	local Info = CloseTweenInfo or CLOSE_INFO

	if not self._Instance.Visible then
		self._IsClosing = false
		self:_ResetVisualState()
		return
	end

	local AnimationId = self:_GetNextAnimationId()
	self._IsClosing = true
	self:_ClearTweens()

	local ScaleTween = self:_PlayTween(self._Scale :: UIScale, Info, {
		Scale = self:_GetOriginalScale() * CLOSE_END_SCALE,
	})
	self:_PlayTween(self._Instance, Info, {
		Position = self:_OffsetUDim2(self:_GetOriginalPosition(), 0, CLOSE_END_OFFSET_Y),
	})
	self:_TweenAccentState(Info, CLOSE_GRADIENT_OFFSET, CLOSE_STROKE_BOOST)

	if not ScaleTween then
		self._Instance.Visible = false
		self._IsClosing = false
		self:_ResetVisualState()
		return
	end

	ScaleTween.Completed:Once(function()
		if self._AnimationId ~= AnimationId then
			return
		end

		self._Instance.Visible = false
		self._IsClosing = false
		self:_ResetVisualState()
	end)
end

function Window:Open(Force: boolean?)
	if UIController.Disabled and not Force then
		return
	end

	UIController._OpenRequestToken += 1
	local RequestToken = UIController._OpenRequestToken
	local HadVisibleWindow = false

	for _, WindowObject in pairs(Registered) do
		if WindowObject == self then
			continue
		end
		if not WindowObject._Instance.Visible then
			continue
		end

		HadVisibleWindow = true
		WindowObject:_CloseAnimation(SWITCH_CLOSE_INFO)
	end

	if not HadVisibleWindow then
		self:_OpenAnimation()
		return
	end

	task.delay(SWITCH_OPEN_DELAY, function()
		if UIController._OpenRequestToken ~= RequestToken then
			return
		end
		if UIController.Disabled and not Force then
			return
		end
		if self._Instance.Visible then
			return
		end

		self:_OpenAnimation()
	end)
end

function Window:Close()
	self:_CloseAnimation()
end

function Window:Toggle()
	if self._Instance.Visible and not self._IsClosing then
		self:Close()
	else
		self:Open()
	end
end

function UIController.Register(Name: string, UIObject: GuiObject): Window
	local Existing = Registered[Name]
	if Existing then
		return Existing
	end

	for _, WindowObject in pairs(Registered) do
		if WindowObject._Instance == UIObject then
			Registered[Name] = WindowObject
			return WindowObject
		end
	end

	local self = setmetatable({}, Window) :: Window
	self._Instance = UIObject
	self._AnimationId = 0
	self._IsClosing = false
	self._Tweens = {}
	self._Strokes = {}
	self._BaseStrokeThickness = {}
	self._Gradients = {}
	self._BaseGradientOffsets = {}
	self:_EnsureAnimationData()

	Registered[Name] = self
	return self
end

function UIController.WaitForRegistered(Name: string, Timeout: number?): Window?
	local TimeoutValue = Timeout or 4
	local Found = Registered[Name]
	if Found then
		return Found
	end

	local Elapsed = 0
	repeat
		Found = Registered[Name]
		Elapsed += RunService.Heartbeat:Wait()
	until Found or Elapsed >= TimeoutValue

	return Found
end

return UIController
