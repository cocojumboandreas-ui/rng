--!nonstrict
-- StarterPlayerScripts/Controllers/UIHoverBinder.luau  (KLIENT)
-- Port z obby ("chrupkie") + rozbudowa: sprezyste press-feedback dla KAZDEGO GuiButton w PlayerGui.
-- hover -> KURCZY (0.93) + OBWODKA rozjasnia sie na bialo; press -> glebiej (0.76, snappy);
-- release -> sprezynuje z przeskokiem (Back/Out). Przyciski BEZ UIStroke dostaja ladna zlota obwodke
-- (jak "Rozpocznij fale"), ktora swieci na hover. Czysto WIZUALNE — nie konsumuje inputu.
-- Binduje AUTOMATYCZNIE (bez tagu) — sweep + DescendantAdded.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIHoverBinder = {}
local LP = Players.LocalPlayer

-- ── "feel" (stroj tu) ──
local RESTING_SCALE = 1.0
local HOVER_SCALE = 0.93
local PRESS_SCALE = 0.76

local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- obwodka na hover (glow) — wspolne dla istniejacych i dodanych obwodek
local HOVER_STROKE_COLOR = Color3.fromRGB(255, 255, 255)
local HOVER_STROKE_THICKNESS_BONUS = 1
local HOVER_STROKE_TRANSPARENCY = 0 -- pelny pop przy hover

-- OBWODKA dodawana przyciskom, ktore jej nie maja (spoczynek): zlota jak akcenty gry, subtelna.
local ADD_MISSING_STROKE = true
local ADDED_STROKE_COLOR = Color3.fromRGB(255, 215, 90)
local ADDED_STROKE_THICKNESS = 2
local ADDED_STROKE_TRANSPARENCY = 0.3

local bound = {}

-- przycisk "widoczny" (warto dodac obwodke): ma tlo / tekst / obrazek. Pomija przezroczyste nakladki-lapacze.
local function looksVisible(b): boolean
	if b.BackgroundTransparency < 0.95 then return true end
	if b:IsA("TextButton") and b.Text ~= "" then return true end
	if b:IsA("ImageButton") and b.Image ~= "" then return true end
	return false
end

-- HUD ziomka (SideButtons) ma wlasny styl ikon (Roll/Build/Skills/Store/Index) — NIE dokladamy
-- tam naszej zlotej obwodki (nie pasuje). Glow istniejacych obwodek na hover zostaje.
local function inFriendHud(inst): boolean
	local sb = LP.PlayerGui:FindFirstChild("SideButtons")
	return sb ~= nil and inst:IsDescendantOf(sb)
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

local function applyStroke(entry)
	local stroke = entry.stroke
	if not stroke then return end
	local color = if entry.hovered then HOVER_STROKE_COLOR else entry.strokeColor0
	local thickness = if entry.hovered then entry.strokeThickness0 + HOVER_STROKE_THICKNESS_BONUS else entry.strokeThickness0
	local transparency = if entry.hovered then HOVER_STROKE_TRANSPARENCY else entry.strokeTransparency0
	if entry.strokeTween then entry.strokeTween:Cancel() end
	entry.strokeTween = TweenService:Create(stroke, HOVER_INFO, { Color = color, Thickness = thickness, Transparency = transparency })
	entry.strokeTween:Play()
end

local function bindButton(inst: Instance)
	if bound[inst] then return end
	if not inst:IsA("GuiButton") then return end

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

	-- OBWODKA: uzyj istniejacej, a jak brak — dodaj zlota (tylko dla widocznych przyciskow).
	local stroke = inst:FindFirstChildOfClass("UIStroke")
	if not stroke and ADD_MISSING_STROKE and looksVisible(inst) and not inFriendHud(inst) then
		stroke = Instance.new("UIStroke")
		stroke.Name = "WR_HoverStroke"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = ADDED_STROKE_COLOR
		stroke.Thickness = ADDED_STROKE_THICKNESS
		stroke.Transparency = ADDED_STROKE_TRANSPARENCY
		stroke.Parent = inst
	end

	local entry = {
		scale = scale, stroke = stroke,
		strokeColor0 = if stroke then stroke.Color else nil,
		strokeThickness0 = if stroke then stroke.Thickness else nil,
		strokeTransparency0 = if stroke then stroke.Transparency else nil,
		hovered = false, pressed = false, tween = nil, strokeTween = nil, conns = {},
	}
	bound[inst] = entry

	local function track(conn) table.insert(entry.conns, conn) end
	track(inst.MouseEnter:Connect(function()
		entry.hovered = true; apply(entry); applyStroke(entry)
	end))
	track(inst.MouseLeave:Connect(function()
		entry.hovered = false; entry.pressed = false; apply(entry); applyStroke(entry)
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
	if entry.strokeTween then entry.strokeTween:Cancel() end
	if entry.scale and entry.scale.Parent then entry.scale.Scale = RESTING_SCALE end
	if entry.stroke and entry.stroke.Parent then
		entry.stroke.Color = entry.strokeColor0
		entry.stroke.Thickness = entry.strokeThickness0
		entry.stroke.Transparency = entry.strokeTransparency0
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
