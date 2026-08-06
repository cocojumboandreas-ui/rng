--!nonstrict
-- StarterPlayerScripts/Controllers/HudBindController.luau  (KLIENT)
-- Wpina DESIGNEROWY HUD (StarterGui.SideButtons, place-owned) w nasze Net eventy.
-- ZASTĘPUJE programistyczny HudController (ten sam zakres: Coins, WaveInfo, OfflineEarns,
-- StartWave/StopWave, licznik rolek, Roll) + modal podsumowania runu. UI robi ziomek w Studio;
-- tu TYLKO odczyt elementów po nazwach + podpięcie zdarzeń (nic nie tworzymy w SideButtons).
-- Etap A wpięcia HUD. Guziki paneli (Skills/Index/Build/Store) dochodzą w kolejnych etapach.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))
local RollRevealController = require(script.Parent:WaitForChild("RollRevealController")) -- bramka anty-spam rolla
local GameConfig = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")) -- offline rollsPerHour

local HudBindController = {}
local LP = Players.LocalPlayer

local function fmt(n)
	n = math.floor(tonumber(n) or 0)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
	else return tostring(n) end
end

-- schodzenie po nazwach z guardem (jak ziomek przemianuje element -> pomijamy, brak crasha)
local function resolve(root, ...)
	local cur = root
	for _, seg in ipairs({ ... }) do
		if not cur then return nil end
		cur = cur:FindFirstChild(seg)
	end
	return cur
end

-- ustaw tekst na labelu I zagnieżdżonych labelach (kit ziomka renderuje tekst warstwowo dla obrysu)
local function setText(inst, txt)
	if not inst then return end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then inst.Text = txt end
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("TextLabel") then c.Text = txt end
	end
end

-- COUNT-UP monet: licznik „tyka" do nowej wartosci (easeOut) zamiast skakac, + POP (UIScale) przy
-- wiekszych skokach (fala/boss/offline). Male przyrosty (per-kill) tylko plynnie ticka, bez popa.
local function makeCoinAnimator(label)
	if not label then return function() end end
	local frame = label.Parent -- CoinsFrame (na nim robimy pop)
	local scale = frame and frame:FindFirstChild("WR_CoinPop")
	if frame and not scale then
		scale = Instance.new("UIScale")
		scale.Name = "WR_CoinPop"
		scale.Scale = 1
		scale.Parent = frame
	end
	local current = 0
	local token = 0
	return function(target, snap)
		target = math.floor(tonumber(target) or 0)
		if snap then
			current = target
			setText(label, fmt(target))
			return
		end
		local delta = target - current
		if delta == 0 then return end
		-- POP tylko przy znaczacym wzroscie (>=100), zeby per-kill nie skakalo
		if delta >= 100 and scale then
			TweenService:Create(scale, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.16 }):Play()
			task.delay(0.1, function()
				TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end)
		end
		token += 1
		local myToken = token
		local from = current
		local dur = math.clamp(math.abs(delta) / 5000, 0.2, 0.6) -- wiekszy skok = dluzszy count-up (cap 0.6s)
		local t0 = os.clock()
		task.spawn(function()
			while true do
				if myToken ~= token then return end -- nowsza zmiana przejela animacje
				local a = math.clamp((os.clock() - t0) / dur, 0, 1)
				local eased = 1 - (1 - a) * (1 - a) -- easeOutQuad
				current = math.floor(from + (target - from) * eased)
				setText(label, fmt(current))
				if a >= 1 then
					current = target
					setText(label, fmt(target))
					return
				end
				task.wait()
			end
		end)
	end
end

-- feedback wciśnięcia (obby-style): press -> 0.9 -> spring back do 1 (UIScale doklejony raz)
local PRESS_DOWN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_UP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local function bindPress(btn)
	-- Press-feedback przejal generyczny UIHoverBinder (hover+press+glow). Zostawiamy no-op,
	-- zeby nie tworzyc konkurencyjnego UIScale na tych samych przyciskach.
	if true then return end
	if not btn or not btn:IsA("GuiButton") then return end
	if btn:FindFirstChild("WR_PressScale") then return end
	local s = Instance.new("UIScale")
	s.Name = "WR_PressScale"; s.Scale = 1; s.Parent = btn
	btn.MouseButton1Down:Connect(function() TweenService:Create(s, PRESS_DOWN, { Scale = 0.9 }):Play() end)
	local function up() TweenService:Create(s, PRESS_UP, { Scale = 1 }):Play() end
	btn.MouseButton1Up:Connect(up)
	btn.MouseLeave:Connect(up)
end

function HudBindController.start()
	local pg = LP:WaitForChild("PlayerGui")
	local sb = pg:WaitForChild("SideButtons", 15)
	if not sb then
		warn("[HudBindController] brak StarterGui.SideButtons — HUD ziomka nie znaleziony")
		return
	end

	-- ── elementy (resolve raz) ──
	local startBtn = resolve(sb, "RightCanvas", "Buttons", "StartWave", "Button")
	local stopBtn = resolve(sb, "RightCanvas", "Buttons", "StopWave", "Button")
	local rollBtn = resolve(sb, "BottomCanvas", "Buttons", "Roll")
	local rollNum = resolve(sb, "BottomCanvas", "Buttons", "Roll", "GoldenRoll", "Number")
	local coinsL = resolve(sb, "LeftCanvas", "Coins", "CoinsFrame", "Coins")
	local setCoins = makeCoinAnimator(coinsL) -- count-up + pop
	-- posiadane rolki (waluta do umiejetnosci) NAD monetami — wypalony blok RollsOwned (ikona=kostka z offline)
	local rollsOwnedL = resolve(sb, "LeftCanvas", "RollsOwned", "CoinsFrame", "Coins")
	local _coinMult = 1 -- aktualny mnoznik monet (z GetStats/StatsSync) — do comba nad graczem

	local offCoins = resolve(sb, "BottomLeftCanvas", "OfflineEarns", "Coins", "Coins")
	local offRolls = resolve(sb, "BottomLeftCanvas", "OfflineEarns", "Rolls", "Rolls")
	local waveNum = resolve(sb, "TopCanvas", "Notifications", "WaveInfo", "WaveNumber")
	local waveInfo = resolve(sb, "TopCanvas", "Notifications", "WaveInfo")
	local waveProgBar = resolve(sb, "TopCanvas", "Notifications", "WaveInfo", "ProgressBar")
	local waveProgText = resolve(sb, "TopCanvas", "Notifications", "WaveInfo", "ProgressBar", "Info", "Text", "Text")

	-- ── akcje (klik -> Net) + feedback wciśnięcia ──
	if startBtn then bindPress(startBtn); startBtn.MouseButton1Click:Connect(function() Net.get("StartWave"):FireServer() end) end
	if stopBtn then bindPress(stopBtn); stopBtn.MouseButton1Click:Connect(function() Net.get("StopWave"):FireServer() end) end

	-- "Zakoncz fale" widoczne TYLKO podczas aktywnej fali; poza fala -> tylko "Rozpocznij fale".
	local startFrame = startBtn and startBtn:FindFirstAncestor("StartWave")
	local stopFrame = stopBtn and stopBtn:FindFirstAncestor("StopWave")
	local function setWaveActiveUI(active)
		if startFrame then startFrame.Visible = not active end
		if stopFrame then stopFrame.Visible = active end
	end
	setWaveActiveUI(false) -- start: idle (tylko Rozpocznij)
	if waveInfo then waveInfo.Visible = false end -- "Wave X" na gorze pojawia sie dopiero po Start Wave
	if rollBtn then bindPress(rollBtn); rollBtn.MouseButton1Click:Connect(function() RollRevealController.requestRoll() end) end

	-- ── guziki paneli -> istniejace kontrolery (startuja PRZED HudBind, wiec .Toggle/.Open juz sa) ──
	local Controllers = script.Parent
	local skillsBtn = resolve(sb, "BottomCanvas", "Buttons", "Skills")
	local indexBtn = resolve(sb, "LeftCanvas", "Buttons", "Index")
	local storeBtn = resolve(sb, "LeftCanvas", "Buttons", "Store")
	local buildBtn = resolve(sb, "BottomCanvas", "Buttons", "Build")

	-- ── WAVE MODE: Buduj niedostepny podczas fali (fale leca ciagiem, brak okna budowania) ──
	local _waveActive = false
	-- toast (komunikat "nie mozna budowac w tej rundzie")
	local toastGui = Instance.new("ScreenGui")
	toastGui.Name = "WR_BuildToast"; toastGui.ResetOnSpawn = false; toastGui.IgnoreGuiInset = true
	toastGui.DisplayOrder = 500; toastGui.Parent = pg
	local toastLbl = Instance.new("TextLabel")
	toastLbl.AnchorPoint = Vector2.new(0.5, 0); toastLbl.Position = UDim2.new(0.5, 0, 0.32, 0)
	toastLbl.Size = UDim2.fromOffset(440, 46); toastLbl.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	toastLbl.BackgroundTransparency = 0.12; toastLbl.BorderSizePixel = 0
	toastLbl.Font = Enum.Font.GothamBold; toastLbl.TextSize = 20; toastLbl.TextColor3 = Color3.fromRGB(255, 120, 120)
	toastLbl.Text = ""; toastLbl.TextTransparency = 1; toastLbl.Visible = false; toastLbl.Parent = toastGui
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 10); tc.Parent = toastLbl
	local tstk = Instance.new("UIStroke"); tstk.Color = Color3.fromRGB(255, 90, 90); tstk.Thickness = 1.5; tstk.Transparency = 0.4; tstk.Parent = toastLbl
	local _toastTok = 0
	local function showToast(text)
		toastLbl.Text = text
		toastLbl.Visible = true; toastLbl.TextTransparency = 1; toastLbl.BackgroundTransparency = 1
		toastLbl.Position = UDim2.new(0.5, 0, 0.31, 0)
		TweenService:Create(toastLbl, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			TextTransparency = 0, BackgroundTransparency = 0.12, Position = UDim2.new(0.5, 0, 0.32, 0),
		}):Play()
		_toastTok += 1
		local tok = _toastTok
		task.delay(1.6, function()
			if tok ~= _toastTok then return end
			TweenService:Create(toastLbl, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.delay(0.4, function() if tok == _toastTok then toastLbl.Visible = false end end)
		end)
	end
	-- przyciemnienie przycisku Build gdy fala trwa (nakladka; Active=false -> klik przechodzi do przycisku -> toast)
	local buildDim = nil
	if buildBtn then
		buildDim = Instance.new("Frame")
		buildDim.Name = "WR_BuildDim"; buildDim.Size = UDim2.fromScale(1, 1)
		buildDim.BackgroundColor3 = Color3.new(0, 0, 0); buildDim.BackgroundTransparency = 0.5
		buildDim.BorderSizePixel = 0; buildDim.ZIndex = 50; buildDim.Active = false; buildDim.Visible = false
		local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(0, 8); dc.Parent = buildDim
		buildDim.Parent = buildBtn
	end
	local function setBuildLocked(locked)
		_waveActive = locked
		if buildDim then buildDim.Visible = locked end
	end

	if skillsBtn then
		bindPress(skillsBtn)
		skillsBtn.MouseButton1Click:Connect(function()
			local ctrl = require(Controllers:FindFirstChild("SkillTreeController"))
			if ctrl and ctrl.Toggle then ctrl.Toggle() end
		end)
	end
	if indexBtn then
		bindPress(indexBtn)
		indexBtn.MouseButton1Click:Connect(function()
			local ctrl = require(Controllers:FindFirstChild("IndexController"))
			if ctrl and ctrl.Open then ctrl.Open() end
		end)
	end
	if buildBtn then
		bindPress(buildBtn)
		buildBtn.MouseButton1Click:Connect(function()
			if _waveActive then
				showToast("You can't build during this round")
				return -- fala trwa -> Buduj zablokowany
			end
			local ctrl = require(Controllers:FindFirstChild("BuildController"))
			if ctrl and ctrl.Toggle then ctrl.Toggle() end
		end)
	end
	if storeBtn then
		bindPress(storeBtn)
		storeBtn.MouseButton1Click:Connect(function()
			local ctrl = require(Controllers:FindFirstChild("StoreController"))
			if ctrl and ctrl.Open then ctrl.Open() end
		end)
	end

	-- ── SZCZESCIE: designerowe ikony w PRAWYM DOLNYM ROGU (BottomRightCanvas.Luck=koniczyna, None=kostka) ──
	local brc = resolve(sb, "BottomRightCanvas")
	local luckSlot = brc and brc:FindFirstChild("Luck")
	local diceSlot = brc and brc:FindFirstChild("None")
	local luckLbl = luckSlot and luckSlot:FindFirstChild("TimeLeft")
	local diceLbl = diceSlot and diceSlot:FindFirstChild("TimeLeft")
	local diceIcon = diceSlot and diceSlot:FindFirstChild("EventIcon")
	if diceIcon then diceIcon.Image = "rbxassetid://92190657341460" end -- None mial pusty obrazek -> kostka
	local function fmtMul(n)
		local sfx = string.format("%.2f", tonumber(n) or 0)
		sfx = sfx:gsub("0+$", ""):gsub("%.$", "")
		return sfx
	end
	-- tooltip rozbicia (hover koniczyny); slot jest w rogu -> tooltip wychodzi w lewo/gore
	local tipSkill, tipIndex
	if luckSlot then
		local tipGui = Instance.new("ScreenGui") -- osobny GUI: slot Luck ma ClipsDescendants + UIScale
		tipGui.Name = "WR_LuckTip"; tipGui.ResetOnSpawn = false; tipGui.IgnoreGuiInset = true; tipGui.DisplayOrder = 120
		tipGui.Parent = pg
		local tip = Instance.new("Frame")
		tip.AnchorPoint = Vector2.new(1, 1); tip.Position = UDim2.new(0.992, 0, 0.9, 0); tip.Size = UDim2.fromOffset(250, 84)
		tip.BackgroundColor3 = Color3.fromRGB(52, 58, 78); tip.BackgroundTransparency = 0.06; tip.BorderSizePixel = 0
		tip.Visible = false; tip.Parent = tipGui
		local tcc = Instance.new("UICorner"); tcc.CornerRadius = UDim.new(0, 10); tcc.Parent = tip
		local tst = Instance.new("UIStroke"); tst.Color = Color3.fromRGB(18, 22, 34); tst.Thickness = 2; tst.Parent = tip
		local function makeTipRow(cap, y, col)
			local c = Instance.new("TextLabel")
			c.Position = UDim2.fromOffset(12, y); c.Size = UDim2.fromOffset(160, 30); c.BackgroundTransparency = 1
			c.Font = Enum.Font.GothamBold; c.TextSize = 16; c.TextColor3 = Color3.fromRGB(210, 214, 230)
			c.TextXAlignment = Enum.TextXAlignment.Left; c.Text = cap; c.ZIndex = 31; c.Parent = tip
			local v = Instance.new("TextLabel")
			v.AnchorPoint = Vector2.new(1, 0); v.Position = UDim2.new(1, -12, 0, y); v.Size = UDim2.fromOffset(76, 30)
			v.BackgroundTransparency = 1; v.Font = Enum.Font.GothamBlack; v.TextSize = 18; v.TextColor3 = col
			v.TextXAlignment = Enum.TextXAlignment.Right; v.Text = "-"; v.ZIndex = 31; v.Parent = tip
			local vs = Instance.new("UIStroke"); vs.Thickness = 2; vs.Color = Color3.new(0, 0, 0); vs.Parent = v
			return v
		end
		tipSkill = makeTipRow("Skill Tree:", 12, Color3.new(1, 1, 1))
		tipIndex = makeTipRow("Index Luck:", 46, Color3.fromRGB(150, 255, 150))
		local hoverBtn = Instance.new("TextButton")
		hoverBtn.Size = UDim2.fromScale(1, 1); hoverBtn.BackgroundTransparency = 1; hoverBtn.Text = ""; hoverBtn.ZIndex = 10; hoverBtn.Parent = luckSlot
		hoverBtn.MouseEnter:Connect(function() tip.Visible = true end)
		hoverBtn.MouseLeave:Connect(function() tip.Visible = false end)
	end
	local function applyLuck(s)
		if type(s) ~= "table" then return end
		if s.coinMult then _coinMult = s.coinMult end -- combo nad graczem skaluje sie mnoznikiem monet
		if luckLbl and s.luck then luckLbl.Text = fmtMul(s.luck) .. "x" end
		if diceLbl and s.rollSpeed then diceLbl.Text = fmtMul(s.rollSpeed) .. "s" end
		if tipSkill and s.luckSkill then tipSkill.Text = "×" .. fmtMul(s.luckSkill) end
		if tipIndex and s.luckIndex then tipIndex.Text = "×" .. fmtMul(s.luckIndex) end
		-- OFFLINE EARNINGS / godzine: coins = offlineRate*coinMult, rolki = config rollsPerHour
		setText(offCoins, fmt((s.offlineRate or 0) * (s.coinMult or 1)))
		local rph = GameConfig.Economy and GameConfig.Economy.offline and GameConfig.Economy.offline.rollsPerHour
		setText(offRolls, fmt(rph or 0))
	end
	task.spawn(function()
		local ok, s = pcall(function() return Net.get("GetStats"):InvokeServer() end)
		if ok then applyLuck(s) end
	end)
	-- initial saldo monet + rolek (CoinsSync/RollsSync to PUSH -> moze wyprzedzic listener; tu PULL)
	task.spawn(function()
		local ok, st = pcall(function() return Net.get("GetSkillState"):InvokeServer() end)
		if ok and type(st) == "table" then
			if st.coins ~= nil then setCoins(st.coins, true) end -- snap na starcie
			if st.spendableRolls ~= nil then
				setText(rollNum, fmt(st.spendableRolls))
				setText(rollsOwnedL, fmt(st.spendableRolls)) -- licznik NAD monetami
			end
		end
	end)

	-- ── waluty / rolki ──
	Net.get("CoinsSync").OnClientEvent:Connect(function(p)
		if p and p.balance ~= nil then setCoins(p.balance) end -- count-up + pop
	end)
	Net.get("RollsSync").OnClientEvent:Connect(function(p)
		if type(p) == "table" and p.spendableRolls ~= nil then
			setText(rollNum, fmt(p.spendableRolls))
			setText(rollsOwnedL, fmt(p.spendableRolls)) -- licznik NAD monetami
		end
	end)
	Net.get("StatsSync").OnClientEvent:Connect(function(s)
		applyLuck(s) -- luck + offline earnings/h (coins & rolki)
	end)

	-- ── COMBO monet NAD GRACZEM (juice): dolicza gold per kill (~realne monety fali), reset po 3s bez killa ──
	local COMBO_COIN_IMG = "rbxassetid://79510076315488" -- ikona monety z UI
	local WCFG, ECFG = GameConfig.Wave, GameConfig.Economy
	local function waveCoinReward(n)
		local w = WCFG.waves[n]
		local base = (w and w.coinReward) or (WCFG.waves[1].coinReward * (((WCFG.scaling and WCFG.scaling.coinGrowth) or 1) ^ (n - 1)))
		if WCFG.bossWave and WCFG.bossWave > 0 and n % WCFG.bossWave == 0 then
			base = base * (WCFG.bossRewardMult or 1)
		end
		return base
	end
	local combo = { total = 0, displayed = 0, lastKill = 0, wave = -1, killed = 0, token = 0 }
	local function buildComboGui()
		local char = LP.Character
		local head = char and char:FindFirstChild("Head")
		if not head then return end
		if combo.gui then combo.gui:Destroy() end
		local gui = Instance.new("BillboardGui")
		gui.Name = "WR_ComboCoins"; gui.Size = UDim2.fromOffset(160, 46)
		gui.StudsOffset = Vector3.new(0, 3.7, 0) -- nad nickiem + licznikiem rolek
		gui.MaxDistance = 90; gui.LightInfluence = 0; gui.Adornee = head
		gui.ResetOnSpawn = false; gui.Enabled = false; gui.Parent = head
		local row = Instance.new("Frame"); row.Size = UDim2.fromScale(1, 1); row.BackgroundTransparency = 1; row.Parent = gui
		local ll = Instance.new("UIListLayout"); ll.FillDirection = Enum.FillDirection.Horizontal
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center; ll.VerticalAlignment = Enum.VerticalAlignment.Center
		ll.Padding = UDim.new(0, 4); ll.Parent = row
		local sc = Instance.new("UIScale"); sc.Parent = row
		local icon = Instance.new("ImageLabel"); icon.LayoutOrder = 1; icon.Size = UDim2.fromOffset(32, 32)
		icon.BackgroundTransparency = 1; icon.Image = COMBO_COIN_IMG; icon.Parent = row
		local label = Instance.new("TextLabel"); label.LayoutOrder = 2; label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, 36); label.BackgroundTransparency = 1; label.Font = Enum.Font.GothamBlack
		label.TextSize = 28; label.TextColor3 = Color3.fromRGB(255, 225, 90); label.Text = "+0"
		local ls = Instance.new("UIStroke"); ls.Color = Color3.new(0, 0, 0); ls.Thickness = 2.6; ls.Parent = label
		label.Parent = row
		combo.gui, combo.label, combo.icon, combo.scale = gui, label, icon, sc
	end
	local function comboShow()
		if not combo.gui or not combo.gui.Parent then buildComboGui() end
		if not combo.gui then return end
		combo.gui.Enabled = true
		if combo.label then combo.label.TextTransparency = 0 end
		if combo.icon then combo.icon.ImageTransparency = 0 end
		if combo.scale then -- pop przy kazdym dolozeniu
			combo.scale.Scale = 1.18
			TweenService:Create(combo.scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	local function comboCountTo(target)
		combo.token += 1; local tok = combo.token
		local from = combo.displayed or 0
		local t0 = os.clock(); local dur = 0.3
		task.spawn(function()
			while combo.token == tok do
				local a = math.clamp((os.clock() - t0) / dur, 0, 1)
				local v = math.floor(from + (target - from) * (1 - (1 - a) * (1 - a)))
				combo.displayed = v
				if combo.label then combo.label.Text = "+" .. fmt(v) end
				if a >= 1 then
					combo.displayed = target
					if combo.label then combo.label.Text = "+" .. fmt(target) end
					break
				end
				task.wait()
			end
		end)
	end
	-- reset po 3s bez killa: zanik -> wyzeruj -> schowaj
	task.spawn(function()
		while true do
			task.wait(0.25)
			if combo.total > 0 and (os.clock() - combo.lastKill) > 3 then
				combo.total = 0; combo.displayed = 0
				if combo.gui and combo.gui.Enabled then
					if combo.label then TweenService:Create(combo.label, TweenInfo.new(0.35), { TextTransparency = 1 }):Play() end
					if combo.icon then TweenService:Create(combo.icon, TweenInfo.new(0.35), { ImageTransparency = 1 }):Play() end
					local g = combo.gui
					task.delay(0.4, function() if combo.total == 0 and g then g.Enabled = false end end)
				end
			end
		end
	end)
	LP.CharacterAdded:Connect(function() -- respawn -> odbuduj + wyzeruj combo
		combo.wave = -1; combo.killed = 0; combo.total = 0; combo.displayed = 0
		task.defer(buildComboGui)
	end)
	if LP.Character then task.defer(buildComboGui) end
	local function comboOnWave(wn, killed, pool)
		wn = wn or 1; killed = killed or 0; pool = pool or 0
		local kills = (wn ~= combo.wave) and killed or (killed - combo.killed)
		combo.wave = wn; combo.killed = killed
		if kills and kills > 0 then
			local per = (waveCoinReward(wn) / math.max(pool, 1) + (ECFG.killReward or 0)) * _coinMult
			combo.total += kills * per
			combo.lastKill = os.clock()
			comboShow()
			comboCountTo(math.floor(combo.total + 0.5))
		end
	end

	-- ── postęp fali (WaveProgress: {waveNumber, killed, pool}) ──
	local function showWave(waveNumber, killed, pool)
		if waveInfo then waveInfo.Visible = true end
		setText(waveNum, "Wave " .. tostring(waveNumber or 1))
		local left = math.max(0, (pool or 0) - (killed or 0))
		setText(waveProgText, left .. " Left")
		if waveProgBar and pool and pool > 0 then
			-- pasek = ILOSC LEFT (pozostali wrogowie): pelny na starcie, ZWEZA sie z kazdym zabitym
			local frac = math.clamp((pool - killed) / pool, 0, 1)
			waveProgBar.Size = UDim2.new(frac, 0, waveProgBar.Size.Y.Scale, waveProgBar.Size.Y.Offset)
		end
	end
	Net.get("WaveProgress").OnClientEvent:Connect(function(p)
		if type(p) == "table" then
			showWave(p.waveNumber, p.killed, p.pool)
			comboOnWave(p.waveNumber, p.killed, p.pool) -- combo monet nad graczem
			setWaveActiveUI(true) -- fala trwa -> pokaz "Zakoncz fale"
			if not _waveActive then
				setBuildLocked(true) -- pierwsza fala runu -> przyciemnij Buduj + zamknij panel jesli otwarty
				local ctrl = require(Controllers:FindFirstChild("BuildController"))
				if ctrl and ctrl.IsBuildMode and ctrl.IsBuildMode() and ctrl.Toggle then ctrl.Toggle() end
			end
		end
	end)
	-- FALE CIAGIEM: WaveEnded to tylko kosmetyka (konfetti/monety robi WaveFxController) — NIE odblokowuje
	-- Buduj ani nie chowa "Wave X", bo zaraz leci nastepna fala. Odblokowanie dopiero na RunSummary (koniec runu).

	-- ── PODSUMOWANIE RUNU: designerowy StarterGui.RoundOver (place-owned; my tylko sterujemy) ──
	-- Modal proceduralny zastapiony kitem ziomka. Payload RunSummary {reason,maxWave,damage,coins,
	-- playerKills,...} -> designer pokazuje 3 statystyki: Monety / Fale / Zabici.
	local roundOver = pg:WaitForChild("RoundOver", 10)
	local roCanvas = roundOver and resolve(roundOver, "Canvas")
	local roVals = roundOver and resolve(roundOver, "Canvas", "Content", "Content", "Values")
	local roMoney = roVals and resolve(roVals, "Money", "Value")
	local roWaves = roVals and resolve(roVals, "Waves", "Value")
	local roKills = roVals and resolve(roVals, "Kills", "Value")
	local roTitle = roundOver and resolve(roundOver, "Canvas", "IconName", "Text")
	local roCollect = roundOver and resolve(roundOver, "Canvas", "Content", "Content", "Collect")
	local roClose = roundOver and resolve(roundOver, "Canvas", "CloseButton")
	if roundOver and roCanvas then
		roundOver.ResetOnSpawn = false
		roundOver.DisplayOrder = 200
		roCanvas.Visible = false -- sterujemy widocznoscia Canvas (ScreenGui zostaje Enabled)
		-- statyczne etykiety -> PL (tylko tekst; layout/styl bez zmian)
		setText(resolve(roVals, "Money", "Text"), "Coins:")
		setText(resolve(roVals, "Waves", "Text"), "Waves:")
		setText(resolve(roVals, "Kills", "Text"), "Kills:")
		setText(resolve(roCollect, "TextLabel"), "Continue")
		local function closeRO() roCanvas.Visible = false end
		if roCollect and roCollect:IsA("GuiButton") then bindPress(roCollect); roCollect.MouseButton1Click:Connect(closeRO) end
		if roClose and roClose:IsA("GuiButton") then roClose.MouseButton1Click:Connect(closeRO) end
	end

	Net.get("RunSummary").OnClientEvent:Connect(function(s)
		if type(s) ~= "table" then return end
		setWaveActiveUI(false) -- koniec runu -> tylko "Rozpocznij fale"
		setBuildLocked(false) -- koniec runu -> Buduj znow dostepny (wracamy do fazy Building)
		if waveInfo then waveInfo.Visible = false end
		if roundOver and roCanvas then
			setText(roMoney, "+" .. fmt(s.coins or 0))
			setText(roWaves, fmt(s.maxWave or 0))
			setText(roKills, fmt(s.kills or 0)) -- kille JEDNOSTEK w runie (nie broni gracza)
			setText(roTitle, (s.reason == "core") and "Base destroyed!" or "Round over!")
			roCanvas.Visible = true
		end
	end)
end

return HudBindController
