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
	local goldFrame = resolve(sb, "BottomCanvas", "Buttons", "Roll", "GoldenRoll") -- bug 11: caly wskaznik (chowany gdy brak skilla Gold Rolls)
	local coinsL = resolve(sb, "LeftCanvas", "Coins", "CoinsFrame", "Coins")
	local setCoins = makeCoinAnimator(coinsL) -- count-up + pop
	-- posiadane rolki (waluta do umiejetnosci) NAD monetami — wypalony blok RollsOwned (ikona=kostka z offline)
	local rollsOwnedL = resolve(sb, "LeftCanvas", "RollsOwned", "CoinsFrame", "Coins")
	local _coinMult = 1 -- aktualny mnoznik monet (z GetStats/StatsSync) — do comba monet

	local offCoins = resolve(sb, "BottomLeftCanvas", "OfflineEarns", "Coins", "Coins")
	local offRolls = resolve(sb, "BottomLeftCanvas", "OfflineEarns", "Rolls", "Rolls")
	local waveNum = resolve(sb, "TopCanvas", "Notifications", "WaveInfo", "WaveNumber")
	local waveInfo = resolve(sb, "TopCanvas", "Notifications", "WaveInfo")
	local waveProgBar = resolve(sb, "TopCanvas", "Notifications", "WaveInfo", "ProgressBar")
	-- bug 5: celuj w ZEWNETRZNA "Info.Text" (ciemny shadow, sizer autoSz=X); setText kaskaduje w dol
	-- na zagniezdzona biala "Text.Text" (gradient) -> OBIE warstwy dostaja te sama liczbe = jeden numer
	-- z cieniem. Wczesniej celowal w wewnetrzna -> zewnetrzna zostawala statyczna ("6 Left") = dwie liczby.
	local waveProgText = resolve(sb, "TopCanvas", "Notifications", "WaveInfo", "ProgressBar", "Info", "Text")

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
		if s.coinMult then _coinMult = s.coinMult end -- combo monet skaluje sie mnoznikiem monet
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
				setText(rollsOwnedL, fmt(st.spendableRolls)) -- licznik kostek NAD monetami (waluta skilli)
			end
		end
		-- bug 11: poczatkowe odliczanie do zlotej rolki (PULL, zeby nie zgubic pushu przed listenerem)
		local gok, g = pcall(function() return Net.get("GetGoldRollState"):InvokeServer() end)
		if gok and type(g) == "table" then
			if goldFrame then goldFrame.Visible = g.owned == true end
			if g.owned and g.remaining ~= nil then setText(rollNum, fmt(g.remaining)) end
		end
	end)

	-- ── waluty / rolki ──
	Net.get("CoinsSync").OnClientEvent:Connect(function(p)
		if p and p.balance ~= nil then setCoins(p.balance) end -- count-up + pop
	end)
	Net.get("RollsSync").OnClientEvent:Connect(function(p)
		if type(p) == "table" and p.spendableRolls ~= nil then
			setText(rollsOwnedL, fmt(p.spendableRolls)) -- licznik kostek NAD monetami (waluta skilli)
		end
	end)
	-- bug 11: "GoldenRoll" na przycisku Roll = ODLICZANIE do nastepnej zlotej rolki (skill Gold Rolls),
	-- NIE waluta skilli. Idzie w dol z kazda rolka; chowamy caly wskaznik gdy gracz nie ma skilla Gold Rolls.
	Net.get("GoldRollSync").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then return end
		if goldFrame then goldFrame.Visible = p.owned == true end
		if p.owned and p.remaining ~= nil then setText(rollNum, fmt(p.remaining)) end
	end)
	Net.get("StatsSync").OnClientEvent:Connect(function(s)
		applyLuck(s) -- luck + offline earnings/h (coins & rolki)
	end)

	-- ── MONEY POP (juice): "+N" monet w losowych miejscach ekranu przy killu (designer MoneyPop.AddCoins) ──
	local WCFG, ECFG = GameConfig.Wave, GameConfig.Economy
	local function waveCoinReward(n)
		local w = WCFG.waves[n]
		local base = (w and w.coinReward) or (WCFG.waves[1].coinReward * (((WCFG.scaling and WCFG.scaling.coinGrowth) or 1) ^ (n - 1)))
		if WCFG.bossWave and WCFG.bossWave > 0 and n % WCFG.bossWave == 0 then
			base = base * (WCFG.bossRewardMult or 1)
		end
		return base
	end
	local combo = { wave = -1, killed = 0 } -- tylko delta killi per WaveProgress tick (bez GUI combo)
	-- COINY podczas fali: przy zbieraniu monet z killa pokazujemy designerowy StarterGui.MoneyPop.AddCoins
	-- w LOSOWYCH miejscach ekranu (strefa akcji nad graczem), zamiast dawnego "+N" combo u gory. Kazdy pop:
	-- pop-in (UIScale) -> unos + zanik -> Destroy. Kille z jednego ticku rozbijamy na kilka popow (suma monet
	-- zachowana). MoneyPop.AddCoins = ukryty szablon (Icon + Wins "+N" z cieniem + UIScale) — klonujemy per pop.
	local POP_CAP = 8 -- max jednoczesnych popow (anti-spam na duzych falach)
	local POP_PER_TICK = 4 -- na ile miejsc rozbic kille z jednego WaveProgress ticku
	local _popActive = 0
	local function moneyPopTemplate()
		local pg = LP:FindFirstChild("PlayerGui")
		local mp = pg and pg:FindFirstChild("MoneyPop")
		if mp then
			mp.ResetOnSpawn = false
			if (mp.DisplayOrder or 0) < 60 then mp.DisplayOrder = 60 end
		end
		return mp, mp and mp:FindFirstChild("AddCoins")
	end
	local function moneyPop(amount)
		if not amount or amount < 1 then return end
		if _popActive >= POP_CAP then return end
		local mp, tmpl = moneyPopTemplate()
		if not tmpl then return end
		_popActive += 1
		local clone = tmpl:Clone()
		clone.Name = "WR_Pop"
		clone.Visible = true
		clone.AnchorPoint = Vector2.new(0.5, 0.5)
		local rx = 0.22 + math.random() * 0.56 -- 0.22..0.78 (z dala od krawedzi/HUD)
		local ry = 0.34 + math.random() * 0.40 -- 0.34..0.74 (strefa nad graczem/akcja)
		clone.Position = UDim2.fromScale(rx, ry)
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("TextLabel") then d.Text = "+" .. fmt(amount) end
		end
		clone.Parent = mp
		local sc = clone:FindFirstChildWhichIsA("UIScale")
		if not sc then sc = Instance.new("UIScale"); sc.Parent = clone end
		sc.Scale = 0.45
		TweenService:Create(sc, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.spawn(function()
			task.wait(0.55)
			TweenService:Create(clone, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(rx, ry - 0.06) }):Play()
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("TextLabel") then TweenService:Create(d, TweenInfo.new(0.45), { TextTransparency = 1 }):Play() end
				if d:IsA("ImageLabel") then TweenService:Create(d, TweenInfo.new(0.45), { ImageTransparency = 1 }):Play() end
				if d:IsA("UIStroke") then TweenService:Create(d, TweenInfo.new(0.45), { Transparency = 1 }):Play() end
			end
			task.wait(0.5)
			clone:Destroy()
			_popActive = math.max(0, _popActive - 1)
		end)
	end
	LP.CharacterAdded:Connect(function() -- respawn -> wyzeruj delty killi
		combo.wave = -1; combo.killed = 0
	end)
	local function comboOnWave(wn, killed, pool)
		wn = wn or 1; killed = killed or 0; pool = pool or 0
		local kills = (wn ~= combo.wave) and killed or (killed - combo.killed)
		combo.wave = wn; combo.killed = killed
		if kills and kills > 0 then
			local per = (waveCoinReward(wn) / math.max(pool, 1) + (ECFG.killReward or 0)) * _coinMult
			local totalCoins = kills * per
			local nPops = math.clamp(kills, 1, POP_PER_TICK)
			local each = totalCoins / nPops
			for _ = 1, nPops do
				moneyPop(math.floor(each + 0.5))
			end
		end
	end

	-- ── postęp fali (WaveProgress: {waveNumber, killed, pool}) ──
	local function showWave(waveNumber, killed, pool)
		if waveInfo then waveInfo.Visible = true end
		setText(waveNum, "Wave " .. tostring(waveNumber or 1))
		local left = math.max(0, (pool or 0) - (killed or 0))
		setText(waveProgText, left .. " Left")
		-- pasek STALY (nie zweza sie z zabijaniem): tylko tekst "N Left" i numer fali sie zmieniaja
		if waveProgBar then
			waveProgBar.Size = UDim2.new(0.35, 0, waveProgBar.Size.Y.Scale, waveProgBar.Size.Y.Offset)
		end
	end
	Net.get("WaveProgress").OnClientEvent:Connect(function(p)
		if type(p) == "table" then
			showWave(p.waveNumber, p.killed, p.pool)
			comboOnWave(p.waveNumber, p.killed, p.pool) -- combo monet na HUD
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
