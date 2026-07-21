--!nonstrict
-- RollReelReveal (KLIENT) — kaskada SEKWENCYJNYCH reeli (styl qwer/ttt).
-- Reel koniczyny ląduje 2x -> STOP -> obok startuje reel 2 (4x) -> STOP -> ... -> reel ITEMU.
-- Rzad rosnie w prawo, wskazniki "lezki" ◀ ▶ rozszerzaja sie by objac caly rzad; latajace koniczyny (VFX).
-- Mnoznik = mutacja (jakosc) + ilosc sztuk. RNG jest serwerowe (RollResult); tu tylko animacja lądowania.
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local RollReel = require(ReplicatedStorage.Framework.UI.RollReel)
local Wobble = require(ReplicatedStorage.Framework.UI.Wobble)
local GameConfig = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig"))

local RollReelReveal = {}

-- ── tuning ──
local SLOT_W = 150
local SLOT_H = 190
local PITCH = 150 -- rozstaw kart w pionie
local CARD_COUNT = 85 -- DLUGA tasma (duzo kart przewija sie)
local WINNER_IDX = 78 -- wygrany daleko -> dlugi zjazd
local SPIN_DUR = 3.4 -- czas reela koniczyny
local ITEM_DUR = 5.2 -- czas reela itemu (najdluzszy)
local ROW_Y = 0.42
local MAX_ROW_W = 1400 -- powyzej -> skaluj rzad w dol (mobile)
local NEUTRAL = Color3.fromRGB(70, 74, 84)
local MUT_COLOR = {
	[2] = Color3.fromRGB(90, 220, 90), [4] = Color3.fromRGB(80, 160, 255), [8] = Color3.fromRGB(255, 205, 80),
	[16] = Color3.fromRGB(255, 150, 60), [32] = Color3.fromRGB(255, 90, 90), [64] = Color3.fromRGB(90, 235, 235),
	[128] = Color3.fromRGB(255, 255, 255),
}
local LADDER = { 2, 4, 8, 16, 32, 64, 128 }

local cfg = {}
local refs = {}
local state = { rolling = false, auto = false, wobble = nil }

-- ── blur (rozmywa tylko swiat 3D, nie GUI) ──
local function setBlur(on)
	local blur = Lighting:FindFirstChild("WR_RevealBlur")
	if on then
		if not blur then blur = Instance.new("BlurEffect"); blur.Name = "WR_RevealBlur"; blur.Parent = Lighting end
		TweenService:Create(blur, TweenInfo.new(0.25), { Size = 20 }):Play()
	elseif blur then
		TweenService:Create(blur, TweenInfo.new(0.25), { Size = 0 }):Play()
	end
end

local function buildViewport(model, parent)
	local vpf = Instance.new("ViewportFrame")
	vpf.BackgroundTransparency = 1
	local cam = Instance.new("Camera"); vpf.CurrentCamera = cam; cam.Parent = vpf
	local clone = model:Clone(); clone.Parent = vpf
	local cframe, size = clone:GetBoundingBox()
	local dist = math.max(size.X, size.Y, size.Z) * 1.7
	cam.CFrame = CFrame.new(cframe.Position + Vector3.new(0, size.Y * 0.08, dist), cframe.Position)
	vpf.Parent = parent
	return vpf
end

local function resolveModel(unitId)
	if cfg.modelProvider then return cfg.modelProvider(unitId) end
	return nil
end

-- ── karty ──
local function makeCloverCard(mult)
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(SLOT_W - 8, PITCH - 12); card.BackgroundTransparency = 1
	local clover = Instance.new("TextLabel")
	clover.BackgroundTransparency = 1; clover.Size = UDim2.fromScale(1, 1); clover.Text = "🍀"; clover.TextScaled = true
	clover.TextColor3 = MUT_COLOR[mult] or Color3.new(1, 1, 1); clover.ZIndex = 2; clover.Parent = card
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1; t.AnchorPoint = Vector2.new(0.5, 0.5); t.Position = UDim2.fromScale(0.5, 0.5)
	t.Size = UDim2.fromScale(0.7, 0.5); t.Font = Enum.Font.GothamBlack; t.Text = mult .. "x"; t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1); t.ZIndex = 3; t.Parent = card
	local st = Instance.new("UIStroke"); st.Thickness = 3; st.Color = Color3.new(0, 0, 0); st.Parent = t
	return card
end

local function makeItemCard(unitId, model)
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(SLOT_W - 8, PITCH - 12); card.BackgroundTransparency = 1
	local u = GameConfig.Units[unitId]
	local rN = u and u.rarityN
	local col = (rN and cfg.resolveTier) and cfg.resolveTier(rN).color or NEUTRAL
	local glow = Instance.new("TextLabel")
	glow.BackgroundTransparency = 1; glow.AnchorPoint = Vector2.new(0.5, 0.5); glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(0.9, 1.4); glow.Font = Enum.Font.GothamBlack; glow.Text = "✦"; glow.TextScaled = true
	glow.TextColor3 = col; glow.TextTransparency = 0.3; glow.ZIndex = 1; glow.Parent = card
	if model then
		local vpf = buildViewport(model, card)
		vpf.AnchorPoint = Vector2.new(0.5, 0.5); vpf.Position = UDim2.fromScale(0.5, 0.48); vpf.Size = UDim2.fromScale(0.7, 0.7); vpf.ZIndex = 2
	end
	if rN then
		local odds = Instance.new("TextLabel")
		odds.AnchorPoint = Vector2.new(0.5, 0); odds.Position = UDim2.fromScale(0.5, 0); odds.Size = UDim2.fromScale(0.8, 0.16)
		odds.BackgroundTransparency = 1; odds.Font = Enum.Font.GothamBlack; odds.TextScaled = true
		odds.Text = "1 in " .. rN; odds.TextColor3 = col; odds.ZIndex = 3; odds.Parent = card
		local s = Instance.new("UIStroke"); s.Thickness = 2; s.Color = Color3.new(0, 0, 0); s.Parent = odds
	end
	local nm = Instance.new("TextLabel")
	nm.AnchorPoint = Vector2.new(0.5, 1); nm.Position = UDim2.fromScale(0.5, 1); nm.Size = UDim2.fromScale(0.98, 0.16)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextScaled = true
	nm.Text = (u and u.displayName) or unitId; nm.TextColor3 = Color3.new(1, 1, 1); nm.ZIndex = 3; nm.Parent = card
	local ns = Instance.new("UIStroke"); ns.Thickness = 2; ns.Color = Color3.new(0, 0, 0); ns.Parent = nm
	return card, col
end

-- ── slot (mini reel pionowy) ──
local function buildSlot(order)
	local win = Instance.new("Frame")
	win.Name = "Slot"; win.Size = UDim2.fromOffset(SLOT_W, SLOT_H); win.BackgroundTransparency = 1
	win.ClipsDescendants = true; win.LayoutOrder = order; win.Parent = refs.row
	local strip = Instance.new("Frame")
	strip.Name = "Strip"; strip.BackgroundTransparency = 1; strip.Position = UDim2.fromOffset(0, 0)
	strip.Size = UDim2.new(1, 0, 0, 0); strip.Parent = win
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical; layout.Padding = UDim.new(0, 12)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center; layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = strip
	-- wygaszanie gora/dol
	local fade = Instance.new("Frame"); fade.Size = UDim2.fromScale(1, 1); fade.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
	fade.BorderSizePixel = 0; fade.ZIndex = 4; fade.Parent = win
	local fg = Instance.new("UIGradient"); fg.Rotation = 90
	fg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0.2) })
	fg.Parent = fade
	return win, strip
end

-- reposycjonuj wskazniki "lezki" by objely caly rzad (rozszerzaja sie)
local function frameIndicators()
	task.wait()
	local w = refs.row.AbsoluteSize.X
	local scale = 1
	if w > MAX_ROW_W then scale = MAX_ROW_W / w end
	refs.rowScale.Scale = scale
	local half = (w * scale) / 2 + 46
	TweenService:Create(refs.indL, TweenInfo.new(0.25), { Position = UDim2.new(0.5, -half, ROW_Y, 0) }):Play()
	TweenService:Create(refs.indR, TweenInfo.new(0.25), { Position = UDim2.new(0.5, half, ROW_Y, 0) }):Play()
end

-- ── latajace koniczyny (VFX szczescia) ──
local function cloverRain(n, color)
	for _ = 1, n do
		task.spawn(function()
			local c = Instance.new("TextLabel")
			c.BackgroundTransparency = 1; c.Text = "🍀"; c.TextScaled = true; c.TextColor3 = color
			c.Size = UDim2.fromOffset(34, 34); c.ZIndex = 2
			local x = math.random(3, 97) / 100
			c.Position = UDim2.new(x, 0, 1.1, 0); c.Rotation = math.random(-40, 40); c.Parent = refs.backdrop
			local dur = 1.1 + math.random() * 0.7
			TweenService:Create(c, TweenInfo.new(dur, Enum.EasingStyle.Linear), { Position = UDim2.new(x, 0, -0.1, 0), Rotation = c.Rotation + math.random(-120, 120), TextTransparency = 1 }):Play()
			task.wait(dur); c:Destroy()
		end)
		task.wait(0.03)
	end
end

-- ── spin jednego slotu (yielduje az wyladuje) ──
local function spinSlot(win, strip, dur)
	task.wait()
	RollReel.play({
		strip = strip, cardWidth = PITCH, winnerIndex = WINNER_IDX,
		windowWidth = win.AbsoluteSize.Y, duration = dur or SPIN_DUR, jitter = 6, vertical = true,
	})
end

-- ── init ──
function RollReelReveal.init(config)
	cfg = config
	local gui = Instance.new("ScreenGui")
	gui.Name = "RollReelReveal"; gui.DisplayOrder = 50; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.Parent = config.parent
	refs.gui = gui

	refs.backdrop = Instance.new("Frame")
	refs.backdrop.Size = UDim2.fromScale(1, 1); refs.backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	refs.backdrop.BackgroundTransparency = 0.5; refs.backdrop.Visible = false; refs.backdrop.Parent = gui

	-- rzad slotow (AutomaticSize -> rosnie w prawo, wysrodkowany), z UIScale do fit
	refs.row = Instance.new("Frame")
	refs.row.Name = "Row"; refs.row.AnchorPoint = Vector2.new(0.5, 0.5); refs.row.Position = UDim2.fromScale(0.5, ROW_Y)
	refs.row.Size = UDim2.fromOffset(0, SLOT_H); refs.row.AutomaticSize = Enum.AutomaticSize.X
	refs.row.BackgroundTransparency = 1; refs.row.Parent = refs.backdrop
	refs.rowScale = Instance.new("UIScale"); refs.rowScale.Parent = refs.row
	local rl = Instance.new("UIListLayout"); rl.FillDirection = Enum.FillDirection.Horizontal
	rl.Padding = UDim.new(0, 10); rl.VerticalAlignment = Enum.VerticalAlignment.Center
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Center; rl.SortOrder = Enum.SortOrder.LayoutOrder; rl.Parent = refs.row

	-- wskazniki "lezki"
	for _, side in ipairs({ { "indL", "▶", -1 }, { "indR", "◀", 1 } }) do
		local ind = Instance.new("TextLabel")
		ind.AnchorPoint = Vector2.new(0.5, 0.5); ind.Position = UDim2.new(0.5, side[3] * 130, ROW_Y, 0)
		ind.Size = UDim2.fromOffset(50, 66); ind.BackgroundTransparency = 1
		ind.Font = Enum.Font.GothamBlack; ind.Text = side[2]; ind.TextScaled = true
		ind.TextColor3 = Color3.fromRGB(255, 255, 255); ind.TextTransparency = 0.1; ind.ZIndex = 6; ind.Parent = refs.backdrop
		local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(120, 190, 255); st.Thickness = 2.5; st.Transparency = 0.15; st.Parent = ind
		refs[side[1]] = ind
	end

	-- podsumowanie mnoznika + ilosci (pod rzedem)
	refs.summary = Instance.new("TextLabel")
	refs.summary.AnchorPoint = Vector2.new(0.5, 0.5); refs.summary.Position = UDim2.fromScale(0.5, ROW_Y + 0.28)
	refs.summary.Size = UDim2.fromOffset(520, 54); refs.summary.BackgroundTransparency = 1
	refs.summary.Font = Enum.Font.GothamBlack; refs.summary.TextScaled = true; refs.summary.Text = ""
	refs.summary.TextColor3 = Color3.fromRGB(255, 235, 120); refs.summary.ZIndex = 6; refs.summary.Visible = false; refs.summary.Parent = refs.backdrop
	local ss = Instance.new("UIStroke"); ss.Thickness = 3; ss.Color = Color3.new(0, 0, 0); ss.Parent = refs.summary

	-- pasek sterowania (widoczny caly czas rolowania)
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1); bar.Position = UDim2.new(0.5, 0, 1, -16); bar.Size = UDim2.fromOffset(440, 96)
	bar.BackgroundTransparency = 1; bar.ZIndex = 6; bar.Parent = refs.backdrop
	local function barBtn(xs, w, h, bg, fg, txt, ts)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(0.5, 0.5); b.Position = UDim2.fromScale(xs, 0.5); b.Size = UDim2.fromOffset(w, h)
		b.BackgroundColor3 = bg; b.TextColor3 = fg; b.Font = Enum.Font.GothamBold; b.TextSize = ts; b.Text = txt; b.ZIndex = 7; b.Parent = bar
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = b
		return b
	end
	refs.autoBtn = barBtn(0.15, 100, 72, Color3.fromRGB(38, 42, 52), Color3.fromRGB(150, 150, 150), "↻\nAuto: WYŁ", 13)
	refs.autoBtn.Activated:Connect(function()
		state.auto = not state.auto
		refs.autoBtn.Text = state.auto and "↻\nAuto: WŁ" or "↻\nAuto: WYŁ"
		refs.autoBtn.TextColor3 = state.auto and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(150, 150, 150)
		if state.auto and not state.rolling and cfg.onRollAgain then cfg.onRollAgain() end
	end)
	local rollaBtn = barBtn(0.5, 116, 88, Color3.fromRGB(240, 240, 240), Color3.fromRGB(30, 30, 30), "🎲\nRolka", 20)
	rollaBtn.Activated:Connect(function()
		if not state.rolling and cfg.onRollAgain then cfg.onRollAgain() end
	end)
	local closeBtn = barBtn(0.85, 96, 72, Color3.fromRGB(35, 38, 48), Color3.fromRGB(255, 255, 255), "✖\nZamknij", 15)
	closeBtn.Activated:Connect(function() state.auto = false; RollReelReveal.close() end)
end

-- ── play: sekwencyjna kaskada ──
local function clearRow()
	for _, ch in ipairs(refs.row:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end
end

local function fillStrip(strip, kind, winnerValue)
	for i = 1, CARD_COUNT do
		local card
		if i == WINNER_IDX then
			-- wygrany: zgodnie z rodzajem tego reela (koniczyna albo item)
			if kind == "clover" then
				card = makeCloverCard(winnerValue)
			else
				local model = resolveModel(winnerValue)
				if model then card = (makeItemCard(winnerValue, model)) end
			end
		else
			-- decoye = MIKS koniczyn i itemow (koniczyna to jedna z opcji obok itemow)
			if math.random() < 0.4 then
				card = makeCloverCard(LADDER[math.random(1, 4)])
			else
				local uid = cfg.decoyIds and cfg.decoyIds[math.random(1, #cfg.decoyIds)]
				local model = uid and resolveModel(uid)
				if model then card = (makeItemCard(uid, model)) end
			end
		end
		if card then card.LayoutOrder = i; card.Parent = strip end
	end
end

function RollReelReveal.play(result)
	if state.rolling then return end
	local unitId = result.unitId or result.id
	local unitModel = resolveModel(unitId)
	if not unitModel then return end
	state.rolling = true
	if state.wobble then state.wobble:Stop(); state.wobble = nil end

	refs.backdrop.Visible = true
	refs.summary.Visible = false
	setBlur(true)
	clearRow()
	refs.rowScale.Scale = 1
	refs.indL.Position = UDim2.new(0.5, -130, ROW_Y, 0)
	refs.indR.Position = UDim2.new(0.5, 130, ROW_Y, 0)

	-- drabina mnoznika z mutacji (2x -> ... -> mult); potem slot itemu
	local mult = result.mutation and result.mutation.mult
	local rungs = {}
	local m = 2
	while m <= (mult or 0) do rungs[#rungs + 1] = m; m *= 2 end

	local order = 0
	-- 1) sloty koniczyn — po kolei
	for _, mv in ipairs(rungs) do
		order += 1
		local win, strip = buildSlot(order)
		fillStrip(strip, "clover", mv)
		frameIndicators()
		task.spawn(cloverRain, 8, MUT_COLOR[mv] or Color3.fromRGB(120, 255, 120))
		spinSlot(win, strip, SPIN_DUR)
		task.wait(0.4) -- STOP przed nastepnym
	end
	-- 2) slot itemu — na koncu, najdluzszy zjazd
	order += 1
	local iwin, istrip = buildSlot(order)
	fillStrip(istrip, "item", unitId)
	frameIndicators()
	spinSlot(iwin, istrip, ITEM_DUR)

	-- (bez info o ilosci w UI — nieistotne; koniczyny same pokazuja mnoznik)
	-- WYBRANY item: nakladka POZA layoutem reela (UIListLayout nadpisywalby Position),
	-- kolysze sie CALY CZAS az do zamkniecia/nastepnej rolki.
	iwin.ClipsDescendants = false
	istrip.Visible = false
	local overlay = (makeItemCard(unitId, unitModel))
	overlay.AnchorPoint = Vector2.new(0.5, 0.5); overlay.Position = UDim2.fromScale(0.5, 0.5); overlay.ZIndex = 5
	overlay.Parent = iwin
	if state.wobble then state.wobble:Stop() end
	state.wobble = Wobble.start(overlay, { rotationAmplitude = 3, rotationSpeed = 4.5, bobAmplitude = 7, bobSpeed = 4, easeIn = 0.15 })

	state.rolling = false
	if state.auto and cfg.onRollAgain then
		task.delay(1.0, function()
			if state.auto and not state.rolling and refs.backdrop.Visible then cfg.onRollAgain() end
		end)
	end
end

function RollReelReveal.close()
	if state.wobble then state.wobble:Stop(); state.wobble = nil end
	setBlur(false)
	refs.backdrop.Visible = false
end

return RollReelReveal
