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

-- feedback wciśnięcia (obby-style): press -> 0.9 -> spring back do 1 (UIScale doklejony raz)
local PRESS_DOWN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_UP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local function bindPress(btn)
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
	local offCoins = resolve(sb, "BottomLeftCanvas", "OfflineEarns", "Coins", "Coins")
	local offRolls = resolve(sb, "BottomLeftCanvas", "OfflineEarns", "Rolls", "Rolls")
	local waveNum = resolve(sb, "TopCanvas", "Notifications", "WaveInfo", "WaveNumber")
	local waveInfo = resolve(sb, "TopCanvas", "Notifications", "WaveInfo")
	local waveProgBar = resolve(sb, "TopCanvas", "Notifications", "WaveInfo", "ProgressBar")
	local waveProgText = resolve(sb, "TopCanvas", "Notifications", "WaveInfo", "ProgressBar", "Info", "Text", "Text")

	-- ── akcje (klik -> Net) + feedback wciśnięcia ──
	if startBtn then bindPress(startBtn); startBtn.MouseButton1Click:Connect(function() Net.get("StartWave"):FireServer() end) end
	if stopBtn then bindPress(stopBtn); stopBtn.MouseButton1Click:Connect(function() Net.get("StopWave"):FireServer() end) end
	if rollBtn then bindPress(rollBtn); rollBtn.MouseButton1Click:Connect(function() Net.get("RollRequest"):FireServer() end) end

	-- ── waluty / rolki ──
	Net.get("CoinsSync").OnClientEvent:Connect(function(p)
		if p and p.balance ~= nil then setText(coinsL, fmt(p.balance)) end
	end)
	Net.get("RollsSync").OnClientEvent:Connect(function(p)
		if type(p) == "table" and p.spendableRolls ~= nil then setText(rollNum, fmt(p.spendableRolls)) end
	end)
	Net.get("StatsSync").OnClientEvent:Connect(function(s)
		if type(s) ~= "table" then return end
		local coinsPerH = (s.offlineRate or 0) * (s.coinMult or 1)
		setText(offCoins, fmt(coinsPerH))
		setText(offRolls, fmt(0))
	end)

	-- ── postęp fali (WaveProgress: {waveNumber, killed, pool}) ──
	local function showWave(waveNumber, killed, pool)
		if waveInfo then waveInfo.Visible = true end
		setText(waveNum, "Wave " .. tostring(waveNumber or 1))
		local left = math.max(0, (pool or 0) - (killed or 0))
		setText(waveProgText, left .. " Left")
		if waveProgBar and pool and pool > 0 then
			local frac = math.clamp(killed / pool, 0.03, 1)
			waveProgBar.Size = UDim2.new(frac, 0, waveProgBar.Size.Y.Scale, waveProgBar.Size.Y.Offset)
		end
	end
	Net.get("WaveProgress").OnClientEvent:Connect(function(p)
		if type(p) == "table" then showWave(p.waveNumber, p.killed, p.pool) end
	end)

	-- ── MODAL PODSUMOWANIA RUNU (przeniesiony z HudController; SideButtons go nie ma) ──
	local modalGui = Instance.new("ScreenGui")
	modalGui.Name = "WR_RunSummary"; modalGui.ResetOnSpawn = false; modalGui.IgnoreGuiInset = true
	modalGui.DisplayOrder = 200; modalGui.Enabled = false; modalGui.Parent = pg
	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1); dim.BackgroundColor3 = Color3.new(0, 0, 0); dim.BackgroundTransparency = 0.4
	dim.BorderSizePixel = 0; dim.Parent = modalGui
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(360, 300); panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(28, 28, 38); panel.BorderSizePixel = 0; panel.Parent = modalGui
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 16); pc.Parent = panel
	local pst = Instance.new("UIStroke"); pst.Color = Color3.fromRGB(255, 215, 90); pst.Thickness = 2; pst.Transparency = 0.3; pst.Parent = panel
	local function lbl(parent, text, size, color, y, xa)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1; l.Font = Enum.Font.GothamBold; l.TextSize = size
		l.TextColor3 = color or Color3.new(1, 1, 1); l.Text = text
		l.TextXAlignment = xa or Enum.TextXAlignment.Center; l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, size + 6); l.Parent = parent
		return l
	end
	local title = lbl(panel, "KONIEC RUNU", 26, Color3.fromRGB(255, 215, 90), 20)
	local subL = lbl(panel, "", 15, Color3.fromRGB(200, 200, 210), 58)
	local function statRow(y, cap, color)
		local capL = lbl(panel, cap, 16, Color3.fromRGB(180, 185, 200), y, Enum.TextXAlignment.Left)
		capL.Position = UDim2.fromOffset(36, y); capL.Size = UDim2.new(1, -72, 0, 28)
		local valL = lbl(panel, "0", 20, color, y, Enum.TextXAlignment.Right)
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
	bindPress(okBtn)
	okBtn.MouseButton1Click:Connect(function() modalGui.Enabled = false end)

	Net.get("RunSummary").OnClientEvent:Connect(function(s)
		if type(s) ~= "table" then return end
		subL.Text = (s.reason == "core") and "Twoja baza została zniszczona" or "Przerwałeś falę"
		waveVal.Text = fmt(s.maxWave or 0)
		dmgVal.Text = fmt(s.damage or 0)
		coinVal.Text = fmt(s.coins or 0)
		modalGui.Enabled = true
	end)
end

return HudBindController
