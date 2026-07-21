--!nonstrict
-- RollReelReveal (KLIENT) — JEDEN wysoki PIONOWY reel (od gory az do przycisku Rolki).
-- Dlugi spin (duzo itemow przelatuje). Koniczyny mnoznika sa DOCZEPIONE do kart itemow
-- (kazda karta = model + rzadkosc + nazwa + rzad koniczyn 2x/4x/[8x]). Wygrany kolysze sie caly czas.
-- RNG serwerowe (RollResult); tu tylko animacja lądowania. Mnoznik = ILOCZYN koniczyn.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local RollReel = require(ReplicatedStorage.Framework.UI.RollReel)
local Wobble = require(ReplicatedStorage.Framework.UI.Wobble)
local GameConfig = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig"))

local RollReelReveal = {}

-- ── tuning ──
local CARD_W = 280
local PITCH = 168 -- rozstaw kart w pionie
local CARD_H = PITCH - 12
local CARD_COUNT = 44 -- DLUGI reel (duzo itemow)
local WINNER_IDX = 38
local SPIN_DUR = 4.7
local WIN_Y = 0.42
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
	return cfg.modelProvider and cfg.modelProvider(unitId) or nil
end

-- KARTA-KONICZYNA (osobna pozycja w rolce — mozna ja wylosowac jak item)
local function makeCloverCard(mult)
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(CARD_W, CARD_H); card.BackgroundTransparency = 1
	local clover = Instance.new("TextLabel")
	clover.BackgroundTransparency = 1; clover.AnchorPoint = Vector2.new(0.5, 0.5); clover.Position = UDim2.fromScale(0.5, 0.5)
	clover.Size = UDim2.fromScale(0.8, 1.15); clover.Text = "🍀"; clover.TextScaled = true
	clover.TextColor3 = MUT_COLOR[mult] or Color3.new(1, 1, 1); clover.ZIndex = 2; clover.Parent = card
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1; t.AnchorPoint = Vector2.new(0.5, 0.5); t.Position = UDim2.fromScale(0.5, 0.52)
	t.Size = UDim2.fromScale(0.55, 0.5); t.Font = Enum.Font.GothamBlack; t.Text = mult .. "x"; t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1); t.ZIndex = 3; t.Parent = card
	local st = Instance.new("UIStroke"); st.Thickness = 3; st.Color = Color3.new(0, 0, 0); st.Parent = t
	return card
end

-- KARTA-ITEM (bez doczepionych koniczyn)
local function makeItemCard(unitId, model)
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(CARD_W, CARD_H); card.BackgroundTransparency = 1
	local u = GameConfig.Units[unitId]
	local rN = u and u.rarityN
	local col = (rN and cfg.resolveTier) and cfg.resolveTier(rN).color or NEUTRAL

	local glow = Instance.new("TextLabel")
	glow.BackgroundTransparency = 1; glow.AnchorPoint = Vector2.new(0.5, 0.5); glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(0.8, 1.3); glow.Font = Enum.Font.GothamBlack; glow.Text = "✦"; glow.TextScaled = true
	glow.TextColor3 = col; glow.TextTransparency = 0.3; glow.ZIndex = 1; glow.Parent = card

	if model then
		local vpf = buildViewport(model, card)
		vpf.AnchorPoint = Vector2.new(0.5, 0.5); vpf.Position = UDim2.fromScale(0.5, 0.5); vpf.Size = UDim2.fromScale(0.55, 0.9); vpf.ZIndex = 2
	end
	if rN then
		local odds = Instance.new("TextLabel")
		odds.AnchorPoint = Vector2.new(0.5, 0); odds.Position = UDim2.fromScale(0.5, 0.02); odds.Size = UDim2.fromScale(0.6, 0.16)
		odds.BackgroundTransparency = 1; odds.Font = Enum.Font.GothamBlack; odds.TextScaled = true
		odds.Text = "1 in " .. rN; odds.TextColor3 = col; odds.ZIndex = 3; odds.Parent = card
		local s = Instance.new("UIStroke"); s.Thickness = 2; s.Color = Color3.new(0, 0, 0); s.Parent = odds
	end
	local nm = Instance.new("TextLabel")
	nm.AnchorPoint = Vector2.new(0.5, 1); nm.Position = UDim2.fromScale(0.5, 1); nm.Size = UDim2.fromScale(0.8, 0.15)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextScaled = true
	nm.Text = (u and u.displayName) or unitId; nm.TextColor3 = Color3.new(1, 1, 1); nm.ZIndex = 3; nm.Parent = card
	local ns = Instance.new("UIStroke"); ns.Thickness = 2; ns.Color = Color3.new(0, 0, 0); ns.Parent = nm
	return card
end

local function cloverRain(n, color)
	for _ = 1, n do
		task.spawn(function()
			local c = Instance.new("TextLabel")
			c.BackgroundTransparency = 1; c.Text = "🍀"; c.TextScaled = true; c.TextColor3 = color
			c.Size = UDim2.fromOffset(32, 32); c.ZIndex = 2
			local x = math.random(3, 97) / 100
			c.Position = UDim2.new(x, 0, 1.1, 0); c.Rotation = math.random(-40, 40); c.Parent = refs.backdrop
			local dur = 1.1 + math.random() * 0.7
			TweenService:Create(c, TweenInfo.new(dur, Enum.EasingStyle.Linear), { Position = UDim2.new(x, 0, -0.1, 0), Rotation = c.Rotation + math.random(-120, 120), TextTransparency = 1 }):Play()
			task.wait(dur); c:Destroy()
		end)
		task.wait(0.03)
	end
end

function RollReelReveal.init(config)
	cfg = config
	local gui = Instance.new("ScreenGui")
	gui.Name = "RollReelReveal"; gui.DisplayOrder = 50; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.Parent = config.parent
	refs.gui = gui

	refs.backdrop = Instance.new("Frame")
	refs.backdrop.Size = UDim2.fromScale(1, 1); refs.backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	refs.backdrop.BackgroundTransparency = 0.5; refs.backdrop.Visible = false; refs.backdrop.Parent = gui

	-- WYSOKIE pionowe okno (od gory az do przycisku Rolki)
	refs.window = Instance.new("Frame")
	refs.window.Name = "Window"; refs.window.AnchorPoint = Vector2.new(0.5, 0.5); refs.window.Position = UDim2.fromScale(0.5, WIN_Y)
	refs.window.Size = UDim2.new(0, CARD_W + 20, 0.8, 0); refs.window.BackgroundTransparency = 1
	refs.window.ClipsDescendants = true; refs.window.Visible = false; refs.window.Parent = refs.backdrop

	refs.strip = Instance.new("Frame")
	refs.strip.Name = "Strip"; refs.strip.BackgroundTransparency = 1; refs.strip.Position = UDim2.fromOffset(0, 0)
	refs.strip.Size = UDim2.new(1, 0, 0, 0); refs.strip.ZIndex = 1; refs.strip.Parent = refs.window
	local layout = Instance.new("UIListLayout"); layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 12); layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Parent = refs.strip

	local fade = Instance.new("Frame"); fade.Size = UDim2.fromScale(1, 1); fade.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
	fade.BorderSizePixel = 0; fade.ZIndex = 4; fade.Parent = refs.window
	local fg = Instance.new("UIGradient"); fg.Rotation = 90
	fg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.12, 1), NumberSequenceKeypoint.new(0.88, 1), NumberSequenceKeypoint.new(1, 0) })
	fg.Parent = fade

	-- wskazniki linii losowania (srodek okna)
	for _, side in ipairs({ { "indL", "▶", -1 }, { "indR", "◀", 1 } }) do
		local ind = Instance.new("TextLabel")
		ind.AnchorPoint = Vector2.new(0.5, 0.5); ind.Position = UDim2.new(0.5, side[3] * (CARD_W / 2 + 40), WIN_Y, 0)
		ind.Size = UDim2.fromOffset(50, 66); ind.BackgroundTransparency = 1
		ind.Font = Enum.Font.GothamBlack; ind.Text = side[2]; ind.TextScaled = true
		ind.TextColor3 = Color3.fromRGB(255, 255, 255); ind.TextTransparency = 0.1; ind.ZIndex = 6; ind.Parent = refs.backdrop
		local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(120, 190, 255); st.Thickness = 2.5; st.Transparency = 0.15; st.Parent = ind
	end

	-- pasek sterowania (widoczny caly czas): Auto | Rolka | Zamknij
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
	rollaBtn.Activated:Connect(function() if not state.rolling and cfg.onRollAgain then cfg.onRollAgain() end end)
	local closeBtn = barBtn(0.85, 96, 72, Color3.fromRGB(35, 38, 48), Color3.fromRGB(255, 255, 255), "✖\nZamknij", 15)
	closeBtn.Activated:Connect(function() state.auto = false; RollReelReveal.close() end)
end

local function clearStrip()
	for _, c in ipairs(refs.strip:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	if refs.overlay then refs.overlay:Destroy(); refs.overlay = nil end
end

function RollReelReveal.play(result)
	if state.rolling then return end
	local unitId = result.unitId or result.id
	local unitModel = resolveModel(unitId)
	if not unitModel then return end
	state.rolling = true
	if state.wobble then state.wobble:Stop(); state.wobble = nil end

	refs.backdrop.Visible = true
	refs.window.Visible = true
	refs.window.ClipsDescendants = true
	setBlur(true)
	clearStrip()

	-- drabina koniczyn (2x -> ... -> mult): kazda to OSOBNY spin (mozesz wylosowac koniczyne)
	local mult = result.mutation and result.mutation.mult
	local rungs = {}
	local m = 2
	while m <= (mult or 0) do rungs[#rungs + 1] = m; m *= 2 end

	-- jeden spin pionowego reela lądujacy na danej pozycji (koniczyna ALBO item)
	local function spinFor(kind, winnerValue, dur)
		clearStrip()
		refs.window.ClipsDescendants = true
		refs.strip.Visible = true
		for i = 1, CARD_COUNT do
			local card
			if kind == "clover" then
				local mv = (i == WINNER_IDX) and winnerValue or LADDER[math.random(1, 4)]
				card = makeCloverCard(mv)
			else
				local uid = (i == WINNER_IDX) and winnerValue or (cfg.decoyIds and cfg.decoyIds[math.random(1, #cfg.decoyIds)])
				local model = uid and resolveModel(uid)
				if model then card = makeItemCard(uid, model) end
			end
			if card then card.LayoutOrder = i; card.Parent = refs.strip end
		end
		task.wait()
		RollReel.play({ strip = refs.strip, cardWidth = PITCH, winnerIndex = WINNER_IDX,
			windowWidth = refs.window.AbsoluteSize.Y, duration = dur, jitter = 8, vertical = true })
	end

	-- sekwencja: koniczyny (kazda osobny szybki spin) -> na koniec DLUGI spin itemu
	for _, mv in ipairs(rungs) do
		task.spawn(cloverRain, 10, MUT_COLOR[mv] or Color3.fromRGB(120, 255, 120))
		spinFor("clover", mv, 1.8)
		task.wait(0.45) -- STOP, pokaz wylosowana koniczyne
	end
	spinFor("item", unitId, SPIN_DUR)

	-- WYGRANY item: nakladka poza layoutem (kolysze sie caly czas)
	refs.window.ClipsDescendants = false
	refs.strip.Visible = false
	refs.overlay = makeItemCard(unitId, unitModel)
	refs.overlay.AnchorPoint = Vector2.new(0.5, 0.5); refs.overlay.Position = UDim2.fromScale(0.5, 0.5); refs.overlay.ZIndex = 5
	refs.overlay.Parent = refs.window
	if state.wobble then state.wobble:Stop() end
	state.wobble = Wobble.start(refs.overlay, { rotationAmplitude = 3, rotationSpeed = 4.5, bobAmplitude = 7, bobSpeed = 4, easeIn = 0.15 })

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
	refs.window.Visible = false
end

return RollReelReveal
