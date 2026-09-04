--!nonstrict
-- StarterPlayerScripts/Controllers/UIHoverBinder.luau  (KLIENT)
-- JEDYNA warstwa "feel" przyciskow (AttentionBob-rotacja + ButtonUI Fazy B sa wylaczone).
-- hover -> lekko KURCZY (0.95) + ROZJASNIA tlo/obrazek; press -> glebiej (0.90); release -> sprezyna.
-- ZERO obrysow: nie dodajemy zadnego UIStroke i NIE dotykamy istniejacych. (Dawniej: bialy stroke na
-- hover rozwalal wyglad = bug 1, a przechwytywanie/odtwarzanie stroke'a kasowalo obrys w Indeksie = bug 3.)
-- Feedback = JASNOSC tla/obrazka, nie obwodka. Snapshot koloru bierzemy przy KAZDYM wejsciu (obsluguje
-- przyciski zmieniajace kolor stanu). Binduje AUTOMATYCZNIE (bez tagu) — sweep + DescendantAdded.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIHoverBinder = {}
local LP = Players.LocalPlayer

-- ── "feel" (stroj tu) ──
local RESTING_SCALE = 1.0
local HOVER_SCALE = 0.95
local PRESS_SCALE = 0.90

local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local COLOR_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local HOVER_BRIGHTEN = 0.14 -- o ile lerpujemy tlo/obrazek ku bieli na hover (jasniej = feedback)

local bound = {}

local function brighten(c: Color3, amt: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amt)
end

local function targetScaleFor(entry): number
	if entry.pressed then
		return PRESS_SCALE
	elseif entry.hovered then
		return HOVER_SCALE
	end
	return RESTING_SCALE
end

local function apply(entry)
	local target = targetScaleFor(entry)
	local info
	if target == RESTING_SCALE then
		info = RELEASE_INFO
	elseif target == PRESS_SCALE then
		info = PRESS_INFO
	else
		info = HOVER_INFO
	end
	if entry.tween then entry.tween:Cancel() end
	entry.tween = TweenService:Create(entry.scale, info, { Scale = target })
	entry.tween:Play()
end

local function applyBrightness(entry)
	local inst = entry.inst
	if entry.colorTween then entry.colorTween:Cancel() end
	local goal = {}
	if entry.hasBg and entry.bgRest then
		goal.BackgroundColor3 = if entry.hovered then brighten(entry.bgRest, HOVER_BRIGHTEN) else entry.bgRest
	end
	if entry.isImage and entry.imgRest then
		goal.ImageColor3 = if entry.hovered then brighten(entry.imgRest, HOVER_BRIGHTEN) else entry.imgRest
	end
	if next(goal) == nil then return end
	entry.colorTween = TweenService:Create(inst, COLOR_INFO, goal)
	entry.colorTween:Play()
end

local function bindButton(inst: Instance)
	if bound[inst] then return end
	if not inst:IsA("GuiButton") then return end
	if inst:GetAttribute("WR_NoHover") then return end -- oznaczone (np. wylaczone karty sklepu) -> bez hover/press

	-- wlasny UIScale (dedykowany, nazwany). Cudzy UIScale (np. QuickScale) -> pomijamy.
	local existing = inst:FindFirstChildOfClass("UIScale")
	local scale
	if existing then
		if existing.Name ~= "WR_HoverScale" then return end
		scale = existing
	else
		scale = Instance.new("UIScale")
		scale.Name = "WR_HoverScale"; scale.Scale = RESTING_SCALE; scale.Parent = inst
	end

	-- feedback robimy sami (jasnosc); wylaczamy AutoButtonColor, zeby Roblox nie dublowal przyciemnieniem
	local autoColor0 = inst.AutoButtonColor
	inst.AutoButtonColor = false

	local isImage = inst:IsA("ImageButton")
	local entry = {
		inst = inst, scale = scale,
		hasBg = inst.BackgroundTransparency < 1,
		isImage = isImage,
		autoColor0 = autoColor0,
		bgRest = nil, imgRest = nil, -- snapshot koloru sprzed hover (ustawiany przy MouseEnter)
		hovered = false, pressed = false, tween = nil, colorTween = nil, conns = {},
	}
	bound[inst] = entry

	local function track(conn) table.insert(entry.conns, conn) end
	track(inst.MouseEnter:Connect(function()
		if inst:GetAttribute("WR_NoHover") then return end
		entry.hovered = true
		if entry.hasBg then entry.bgRest = inst.BackgroundColor3 end
		if entry.isImage then entry.imgRest = inst.ImageColor3 end
		apply(entry); applyBrightness(entry)
	end))
	track(inst.MouseLeave:Connect(function()
		entry.hovered = false; entry.pressed = false; apply(entry); applyBrightness(entry)
	end))
	track(inst.MouseButton1Down:Connect(function()
		entry.pressed = true; apply(entry)
	end))
	track(inst.MouseButton1Up:Connect(function()
		entry.pressed = false; apply(entry)
	end))
end

local function unbindButton(inst: Instance)
	local entry = bound[inst]
	if not entry then return end
	bound[inst] = nil
	for _, conn in ipairs(entry.conns) do conn:Disconnect() end
	if entry.tween then entry.tween:Cancel() end
	if entry.colorTween then entry.colorTween:Cancel() end
	if entry.scale and entry.scale.Parent then entry.scale.Scale = RESTING_SCALE end
	if entry.inst and entry.inst.Parent then
		if entry.hasBg and entry.bgRest then entry.inst.BackgroundColor3 = entry.bgRest end
		if entry.isImage and entry.imgRest then entry.inst.ImageColor3 = entry.imgRest end
		entry.inst.AutoButtonColor = entry.autoColor0
	end
end

function UIHoverBinder.start()
	local pg = LP:WaitForChild("PlayerGui")
	for _, d in ipairs(pg:GetDescendants()) do
		if d:IsA("GuiButton") then bindButton(d) end
	end
	pg.DescendantAdded:Connect(function(d)
		if d:IsA("GuiButton") then bindButton(d) end
	end)
	pg.DescendantRemoving:Connect(unbindButton)
end

return UIHoverBinder
