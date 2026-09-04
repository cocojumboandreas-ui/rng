--!nonstrict
-- StarterPlayerScripts/Controllers/BossController.luau  (klient)
-- Pasek HP bossa w DESIGNEROWYM HUD: SideButtons.TopCanvas.Notifications.BossBar
-- (Bar: BossName / BossHP / Progress=fill). Pokazuje sie na boss-fali (Net.BossHP),
-- znika po pokonaniu (BossDefeated -> flourish), koncu fali (WaveEnded) lub gdy boss
-- przestaje slac HP. Nie tworzymy nic w SideButtons — tylko sterujemy elementami po nazwach.
-- KOSMETYKA D: intro-pop paska (Back), puls przy niskim HP (<25%), odroznienie mini-bossa (kolor blekit).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))

local BossController = {}
local _lastHP = 0

local BIG_NAME_COLOR = Color3.fromRGB(255, 220, 120) -- duzy boss = zloty
local MINI_NAME_COLOR = Color3.fromRGB(150, 225, 255) -- mini-boss (elita) = blekit
local LOW_HP_FRAC = 0.25 -- ponizej tego progu pasek pulsuje na czerwono (blisko smierci)

local function setText(inst, txt)
	if not inst then return end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then inst.Text = txt end
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("TextLabel") then c.Text = txt end
	end
end

local function setColor(inst, col)
	if not inst then return end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then inst.TextColor3 = col end
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("TextLabel") then c.TextColor3 = col end
	end
end

-- ZABEZPIECZENIE (bug 6): czysc emoji z nazwy wyswietlanej w GUI (emotki rozwalaly uklad paska).
-- Usuwa kazdy codepoint >= U+2190 (strzalki/symbole/emoji, w tym gwiazdki i militarne), zostawia
-- ASCII + Latin. Pusty/blad utf8 -> zwroc oryginal. Uzywac na KAZDEJ nazwie bossa przed setText.
local function stripEmoji(s)
	if type(s) ~= "string" then return s end
	local ok, r = pcall(function()
		local out = {}
		for _, cp in utf8.codes(s) do
			if cp < 0x2190 then
				out[#out + 1] = utf8.char(cp)
			end
		end
		return (table.concat(out):gsub("^%s+", ""):gsub("%s+$", ""))
	end)
	if not ok or r == "" then return s end
	return r
end

function BossController.start()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local sb = pg:WaitForChild("SideButtons", 15)
	local notif = sb and sb:FindFirstChild("TopCanvas") and sb.TopCanvas:FindFirstChild("Notifications")
	local bossBar = notif and notif:FindFirstChild("BossBar")
	local bar = bossBar and bossBar:FindFirstChild("Bar")
	local bossName = bar and bar:FindFirstChild("BossName")
	local bossHP = bar and bar:FindFirstChild("BossHP")
	local progress = bar and bar:FindFirstChild("Progress")
	if not bossBar then
		warn("[BossController] brak designerowego BossBar (SideButtons) — pasek bossa nieaktywny")
		return
	end

	-- INTRO: skala-pop paska przy wejsciu bossa (UIScale doklejony raz; Back = elastyczny „wskok").
	local introScale = bar and bar:FindFirstChild("WR_BossIntro")
	if bar and not introScale then
		introScale = Instance.new("UIScale")
		introScale.Name = "WR_BossIntro"
		introScale.Scale = 1
		introScale.Parent = bar
	end
	-- LOW-HP: czerwona nakladka pulsujaca gdy HP bossa spada nisko (sygnal „zaraz padnie").
	local lowOverlay = bar and bar:FindFirstChild("WR_BossLowHp")
	if bar and not lowOverlay then
		lowOverlay = Instance.new("Frame")
		lowOverlay.Name = "WR_BossLowHp"
		lowOverlay.Size = UDim2.fromScale(1, 1)
		lowOverlay.BackgroundColor3 = Color3.fromRGB(255, 55, 55)
		lowOverlay.BackgroundTransparency = 1
		lowOverlay.BorderSizePixel = 0
		lowOverlay.ZIndex = 2 -- nad tlem paska, pod tekstem (BossName/HP maja wyzszy ZIndex)
		local lc = Instance.new("UICorner")
		lc.CornerRadius = UDim.new(0, 8)
		lc.Parent = lowOverlay
		lowOverlay.Parent = bar
	end
	local _lowHp = false

	-- flourish „BOSS POKONANY!" (własny mały overlay; designer nie ma tego elementu)
	local fgui = Instance.new("ScreenGui")
	fgui.Name = "WR_BossFlourish"; fgui.ResetOnSpawn = false; fgui.IgnoreGuiInset = true; fgui.DisplayOrder = 150
	fgui.Parent = pg
	local flourish = Instance.new("TextLabel")
	flourish.Size = UDim2.fromScale(0.7, 0.1); flourish.Position = UDim2.fromScale(0.15, 0.28)
	flourish.BackgroundTransparency = 1; flourish.TextColor3 = Color3.fromRGB(255, 220, 120)
	flourish.Font = Enum.Font.GothamBlack; flourish.TextScaled = true; flourish.Text = "BOSS DEFEATED!"
	local fst = Instance.new("UIStroke"); fst.Thickness = 3; fst.Color = Color3.new(0, 0, 0); fst.Parent = flourish
	flourish.Visible = false; flourish.Parent = fgui

	local progH = progress and progress.Size.Y or UDim.new(1, 0)
	local function setFrac(frac)
		if progress then
			progress.Size = UDim2.new(math.clamp(frac, 0, 1), 0, progH.Scale, progH.Offset)
		end
	end
	-- ── SHAKE EKRANU "boss wbija" (TYLKO duzy boss co 20 fal; mini-boss NIE trzesie) ──
	local Workspace = game:GetService("Workspace")
	local _shakeStart, _shakeDur, _shakeAmp = 0, 0, 0
	local _bigShaken = false -- shake RAZ na pojawienie sie danego duzego bossa (reset w hide)
	local function startShake(amp, dur) _shakeAmp = amp; _shakeDur = dur; _shakeStart = os.clock() end
	RunService:BindToRenderStep("WR_BossShake", Enum.RenderPriority.Camera.Value + 1, function()
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local t = (os.clock() - _shakeStart) / math.max(_shakeDur, 0.01)
		if t >= 1 then return end -- po czasie: brak offsetu (kamera nietknieta)
		local decay = _shakeAmp * (1 - t) -- amplituda opada do 0 (punch -> wygasa)
		local n = os.clock() * 22
		cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(math.noise(n, 0.5) * decay), math.rad(math.noise(0.5, n) * decay), math.rad(math.noise(n, n) * decay * 0.4))
	end)

	local _visible = false
	local function playIntro()
		if not introScale then return end
		introScale.Scale = 0.6
		TweenService:Create(introScale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	local function show()
		if not _visible then
			_visible = true
			playIntro() -- pop TYLKO na przejsciu ukryty->widoczny (nie co tick HP)
		end
		bossBar.Visible = true
	end
	local function hide()
		bossBar.Visible = false
		_bigShaken = false
		_visible = false
		_lowHp = false
		if lowOverlay then lowOverlay.BackgroundTransparency = 1 end
	end

	Net.get("BossHP").OnClientEvent:Connect(function(p)
		if not p or not p.maxHp or p.maxHp <= 0 then return end
		local frac = p.hp / p.maxHp
		setFrac(frac)
		_lowHp = frac <= LOW_HP_FRAC
		setText(bossHP, ("%d / %d"):format(math.max(0, math.floor(p.hp + 0.5)), math.floor(p.maxHp + 0.5)))
		if bossName then
			local nm = stripEmoji(p.name or "BOSS") -- bug 6: czysc emoji z nazwy (rozwalaly uklad paska)
			setText(bossName, nm)
			setColor(bossName, p.big and BIG_NAME_COLOR or MINI_NAME_COLOR) -- mini-boss = blekit (bez emoji)
		end
		if p.big and not _bigShaken then _bigShaken = true; startShake(3.5, 0.6) end -- DUZY boss wbija -> trzasnij ekranem (mini NIE)
		show()
		_lastHP = os.clock()
	end)

	Net.get("BossDefeated").OnClientEvent:Connect(function()
		hide()
		flourish.Visible = true
		task.delay(2.5, function() if flourish then flourish.Visible = false end end)
	end)

	Net.get("WaveEnded").OnClientEvent:Connect(function()
		hide()
	end)

	-- pętla: (1) staleness — boss przestał słać HP -> schowaj po ~0.5s; (2) puls low-HP (czerwona nakladka).
	RunService.Heartbeat:Connect(function()
		if bossBar.Visible and os.clock() - _lastHP > 0.5 then
			hide()
			return
		end
		if lowOverlay then
			if _lowHp and bossBar.Visible then
				-- sinusoidalny puls: krycie 0.9..0.5 (subtelny czerwony oddech, nie zaslania tekstu)
				local pulse = 0.7 + 0.2 * math.sin(os.clock() * 9)
				lowOverlay.BackgroundTransparency = pulse
			elseif lowOverlay.BackgroundTransparency ~= 1 then
				lowOverlay.BackgroundTransparency = 1
			end
		end
	end)
end

return BossController
