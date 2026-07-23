--!nonstrict
-- StarterPlayerScripts/Controllers/HudController.luau  (KLIENT — pelny HUD wg wzoru ww.png)
-- Chrome informacyjny + przyciski, ktorych nie tworza inne kontrolery:
--   gora-lewo: monety (CoinsSync). lewo: Sklep (placeholder) + [Indeks/Skille sa w swoich kontrolerach].
--   dol-lewo: luck (StatsSync) + cooldown rolki. dol-srodek: liczba rolek nad Rolka (RollsSync).
--   nad postacia: laczna liczba rolek (lifetimeRolls). dol-prawo: zarobki offline/h.
--   prawo-srodek: Rozpocznij fale (StartWave) + Automatyczna fala (LOCKED do skilla).
-- Serwer autorytatywny; tu tylko prezentacja + intencje.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local HudController = {}
local LP = Players.LocalPlayer

local function fmt(n)
	n = math.floor(tonumber(n) or 0)
	if n >= 1e6 then return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
	else return tostring(n) end
end

local function pill(parent, size, pos, anchor)
	local f = Instance.new("Frame")
	f.Size = size; f.Position = pos; f.AnchorPoint = anchor or Vector2.new(0, 0)
	f.BackgroundColor3 = Color3.fromRGB(24, 24, 32); f.BackgroundTransparency = 0.15; f.BorderSizePixel = 0
	f.Parent = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = f
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(0, 0, 0); st.Thickness = 1.5; st.Transparency = 0.4; st.Parent = f
	return f
end

local function label(parent, text, size2, color, xa)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1); l.BackgroundTransparency = 1
	l.TextColor3 = color or Color3.new(1, 1, 1); l.Font = Enum.Font.GothamBold; l.TextScaled = false
	l.TextSize = size2 or 18; l.Text = text; l.TextXAlignment = xa or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

function HudController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_Hud"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 20
	gui.Parent = LP:WaitForChild("PlayerGui")

	-- warstwa NAD rewealem (DisplayOrder 60 > reveal 50): zarobki offline zostaja jasne w trakcie rolowania
	local guiOver = Instance.new("ScreenGui")
	guiOver.Name = "WR_HudOver"; guiOver.ResetOnSpawn = false; guiOver.IgnoreGuiInset = true; guiOver.DisplayOrder = 60
	guiOver.Parent = LP:WaitForChild("PlayerGui")

	-- ── gora-lewo: monety ──
	local coinF = pill(gui, UDim2.fromOffset(160, 44), UDim2.fromOffset(12, 12))
	local coinL = label(coinF, "🪙 0", 20, Color3.fromRGB(255, 215, 90), Enum.TextXAlignment.Left)
	coinL.Position = UDim2.fromOffset(12, 0); coinL.Size = UDim2.new(1, -16, 1, 0)

	-- ── lewo: Sklep (placeholder; Indeks/Skille tworza ich kontrolery) ──
	local sklep = Instance.new("TextButton")
	sklep.Size = UDim2.fromOffset(120, 54); sklep.AnchorPoint = Vector2.new(0, 0.5); sklep.Position = UDim2.new(0, 16, 0.5, -60)
	sklep.BackgroundColor3 = Color3.fromRGB(150, 60, 130); sklep.TextColor3 = Color3.new(1, 1, 1)
	sklep.Font = Enum.Font.GothamBold; sklep.TextSize = 16; sklep.Text = "🛒 Sklep"; sklep.Parent = gui
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 10); sc.Parent = sklep

	-- ── dol-lewo: luck + cooldown rolki ──
	local luckF = pill(gui, UDim2.fromOffset(120, 34), UDim2.new(0, 12, 1, -58), Vector2.new(0, 1))
	local luckL = label(luckF, "🍀 1.0x", 16, Color3.fromRGB(150, 255, 150), Enum.TextXAlignment.Left)
	luckL.Position = UDim2.fromOffset(10, 0); luckL.Size = UDim2.new(1, -12, 1, 0)
	local cdF = pill(gui, UDim2.fromOffset(120, 34), UDim2.new(0, 12, 1, -20), Vector2.new(0, 1))
	local cdL = label(cdF, "🎲 —", 16, Color3.fromRGB(200, 220, 255), Enum.TextXAlignment.Left)
	cdL.Position = UDim2.fromOffset(10, 0); cdL.Size = UDim2.new(1, -12, 1, 0)

	-- ── dol-srodek: liczba rolek do wydania (nad Rolka) ──
	local rollsF = pill(gui, UDim2.fromOffset(120, 30), UDim2.new(0.5, 0, 1, -102), Vector2.new(0.5, 1))
	local rollsL = label(rollsF, "🎲 0", 16, Color3.fromRGB(255, 255, 255))

	-- ── prawo-srodek: Rozpocznij fale + Automatyczna fala (LOCKED) ──
	local waveBtn = Instance.new("TextButton")
	waveBtn.Size = UDim2.fromOffset(190, 50); waveBtn.AnchorPoint = Vector2.new(1, 0.5); waveBtn.Position = UDim2.new(1, -16, 0.5, -30)
	waveBtn.BackgroundColor3 = Color3.fromRGB(70, 170, 60); waveBtn.TextColor3 = Color3.new(1, 1, 1)
	waveBtn.Font = Enum.Font.GothamBold; waveBtn.TextSize = 17; waveBtn.Text = "Rozpocznij falę"; waveBtn.Parent = gui
	local wc = Instance.new("UICorner"); wc.CornerRadius = UDim.new(0, 10); wc.Parent = waveBtn
	waveBtn.MouseButton1Click:Connect(function()
		Net.get("StartWave"):FireServer()
	end)

	local autoBtn = Instance.new("TextButton")
	autoBtn.Size = UDim2.fromOffset(190, 50); autoBtn.AnchorPoint = Vector2.new(1, 0.5); autoBtn.Position = UDim2.new(1, -16, 0.5, 30)
	autoBtn.BackgroundColor3 = Color3.fromRGB(120, 50, 50); autoBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
	autoBtn.Font = Enum.Font.GothamBold; autoBtn.TextSize = 15; autoBtn.Text = "🔒 Automatyczna fala"; autoBtn.Parent = gui
	local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(0, 10); ac.Parent = autoBtn
	local autoToast = label(gui, "", 16, Color3.fromRGB(255, 180, 120))
	autoToast.AnchorPoint = Vector2.new(1, 0.5); autoToast.Position = UDim2.new(1, -16, 0.5, 66); autoToast.Size = UDim2.fromOffset(220, 24); autoToast.Visible = false
	autoBtn.MouseButton1Click:Connect(function()
		autoToast.Text = "Odblokuj w Umiejętnościach"; autoToast.Visible = true
		task.delay(2, function() autoToast.Visible = false end)
	end)

	-- ── dol-prawo: zarobki offline / h (warstwa NAD rewealem — zostaje jasne w trakcie rolowania) ──
	local stopBtn = Instance.new("TextButton")
		stopBtn.Size = UDim2.fromOffset(150, 40); stopBtn.AnchorPoint = Vector2.new(1, 0); stopBtn.Position = UDim2.new(1, -16, 0, 12)
		stopBtn.BackgroundColor3 = Color3.fromRGB(200, 55, 55); stopBtn.TextColor3 = Color3.new(1, 1, 1)
		stopBtn.Font = Enum.Font.GothamBold; stopBtn.TextSize = 16; stopBtn.Text = "⛔ Zakończ falę"; stopBtn.Parent = gui
		local stc = Instance.new("UICorner"); stc.CornerRadius = UDim.new(0, 10); stc.Parent = stopBtn
		stopBtn.MouseButton1Click:Connect(function()
			Net.get("StopWave"):FireServer()
		end)

		local modalGui = Instance.new("ScreenGui")
		modalGui.Name = "WR_RunSummary"; modalGui.ResetOnSpawn = false; modalGui.IgnoreGuiInset = true
		modalGui.DisplayOrder = 80; modalGui.Enabled = false; modalGui.Parent = LP:WaitForChild("PlayerGui")
		local dim = Instance.new("Frame")
		dim.Size = UDim2.fromScale(1, 1); dim.BackgroundColor3 = Color3.new(0, 0, 0); dim.BackgroundTransparency = 0.4
		dim.BorderSizePixel = 0; dim.Parent = modalGui
		local panel = Instance.new("Frame")
		panel.Size = UDim2.fromOffset(360, 300); panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.fromScale(0.5, 0.5)
		panel.BackgroundColor3 = Color3.fromRGB(28, 28, 38); panel.BorderSizePixel = 0; panel.Parent = modalGui
		local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 16); pc.Parent = panel
		local pst = Instance.new("UIStroke"); pst.Color = Color3.fromRGB(255, 215, 90); pst.Thickness = 2; pst.Transparency = 0.3; pst.Parent = panel
		local title = label(panel, "KONIEC RUNU", 26, Color3.fromRGB(255, 215, 90))
		title.Position = UDim2.fromOffset(0, 20); title.Size = UDim2.new(1, 0, 0, 40)
		local subL = label(panel, "", 15, Color3.fromRGB(200, 200, 210))
		subL.Position = UDim2.fromOffset(0, 58); subL.Size = UDim2.new(1, 0, 0, 20)
		local function statRow(y, cap, color)
			local capL = label(panel, cap, 16, Color3.fromRGB(180, 185, 200), Enum.TextXAlignment.Left)
			capL.Position = UDim2.fromOffset(36, y); capL.Size = UDim2.new(1, -72, 0, 28)
			local valL = label(panel, "0", 20, color or Color3.new(1, 1, 1), Enum.TextXAlignment.Right)
			valL.Position = UDim2.fromOffset(36, y); valL.Size = UDim2.new(1, -72, 0, 28)
			return valL
		end
		local waveVal = statRow(96, "🌊 Najdalsza fala", Color3.fromRGB(120, 200, 255))
		local dmgVal = statRow(134, "⚔️ Zadane obrażenia", Color3.fromRGB(255, 150, 120))
		local coinVal = statRow(172, "🪙 Zarobione monety", Color3.fromRGB(255, 215, 90))
		local okBtn = Instance.new("TextButton")
		okBtn.Size = UDim2.fromOffset(200, 46); okBtn.AnchorPoint = Vector2.new(0.5, 1); okBtn.Position = UDim2.new(0.5, 0, 1, -20)
		okBtn.BackgroundColor3 = Color3.fromRGB(70, 170, 60); okBtn.TextColor3 = Color3.new(1, 1, 1)
		okBtn.Font = Enum.Font.GothamBold; okBtn.TextSize = 18; okBtn.Text = "OK"; okBtn.Parent = panel
		local okc = Instance.new("UICorner"); okc.CornerRadius = UDim.new(0, 10); okc.Parent = okBtn
		okBtn.MouseButton1Click:Connect(function() modalGui.Enabled = false end)

		Net.get("RunSummary").OnClientEvent:Connect(function(s)
			if type(s) ~= "table" then return end
			subL.Text = (s.reason == "core") and "Twoja baza zostala zniszczona" or "Przerwales fale"
			waveVal.Text = fmt(s.maxWave or 0)
			dmgVal.Text = fmt(s.damage or 0)
			coinVal.Text = fmt(s.coins or 0)
			modalGui.Enabled = true
		end)

		local offF = pill(guiOver, UDim2.fromOffset(210, 66), UDim2.new(1, -12, 1, -12), Vector2.new(1, 1))
	local offTitle = label(offF, "Zarobki offline (na godzinę)", 13, Color3.fromRGB(150, 255, 150))
	offTitle.Position = UDim2.fromOffset(0, 4); offTitle.Size = UDim2.new(1, 0, 0, 20)
	local offVals = label(offF, "🪙 0   🎲 0", 16, Color3.new(1, 1, 1))
	offVals.Position = UDim2.fromOffset(0, 30); offVals.Size = UDim2.new(1, 0, 0, 28)

	-- ── nad postacia: laczna liczba rolek (lifetimeRolls) ──
	local overhead, overheadLabel = nil, nil
	local function ensureOverhead()
		local char = LP.Character
		local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
		if not head then return end
		if overhead and overhead.Adornee == head then return end
		if overhead then overhead:Destroy() end
		overhead = Instance.new("BillboardGui")
		overhead.Name = "WR_RollsTag"; overhead.Size = UDim2.fromOffset(120, 26); overhead.StudsOffset = Vector3.new(0, 3, 0)
		overhead.AlwaysOnTop = true; overhead.Adornee = head; overhead.Parent = head
		overheadLabel = label(overhead, "🎲 0", 16, Color3.fromRGB(255, 255, 255))
		local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = Color3.new(0, 0, 0); st.Parent = overheadLabel
	end

	-- ── wiring danych ──
	Net.get("CoinsSync").OnClientEvent:Connect(function(p)
		if p and p.balance ~= nil then coinL.Text = "🪙 " .. fmt(p.balance) end
	end)
	Net.get("RollsSync").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then return end
		if p.spendableRolls ~= nil then rollsL.Text = "🎲 " .. fmt(p.spendableRolls) end
		ensureOverhead()
		if overheadLabel and p.lifetimeRolls ~= nil then
			overheadLabel.Text = "🎲 " .. fmt(p.lifetimeRolls)
		end
	end)
	Net.get("StatsSync").OnClientEvent:Connect(function(s)
		if type(s) ~= "table" then return end
		if s.luck then luckL.Text = ("🍀 %.2fx"):format(s.luck) end
		if s.rollSpeed then cdL.Text = ("🎲 %.2fs"):format(s.rollSpeed) end
		-- zarobki/h: monety = offlineRate * coinMult; rolki/h = 0 (offline spins = layer-2)
		local coinsPerH = (s.offlineRate or 0) * (s.coinMult or 1)
		offVals.Text = ("🪙 %s   🎲 %s"):format(fmt(coinsPerH), fmt(0))
	end)

	LP.CharacterAdded:Connect(function() task.wait(0.3); ensureOverhead() end)
	if LP.Character then ensureOverhead() end
end

return HudController
