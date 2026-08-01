--!nonstrict
-- StarterPlayerScripts/Controllers/BossController.luau  (klient)
-- Pasek HP bossa w DESIGNEROWYM HUD: SideButtons.TopCanvas.Notifications.BossBar
-- (Bar: BossName / BossHP / Progress=fill). Pokazuje sie na boss-fali (Net.BossHP),
-- znika po pokonaniu (BossDefeated -> flourish), koncu fali (WaveEnded) lub gdy boss
-- przestaje slac HP. Nie tworzymy nic w SideButtons — tylko sterujemy elementami po nazwach.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))

local BossController = {}
local _lastHP = 0

local function setText(inst, txt)
	if not inst then return end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then inst.Text = txt end
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("TextLabel") then c.Text = txt end
	end
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

	local function show() bossBar.Visible = true end
	local function hide() bossBar.Visible = false; _bigShaken = false end

	Net.get("BossHP").OnClientEvent:Connect(function(p)
		if not p or not p.maxHp or p.maxHp <= 0 then return end
		setFrac(p.hp / p.maxHp)
		setText(bossHP, ("%d / %d"):format(math.max(0, math.floor(p.hp + 0.5)), math.floor(p.maxHp + 0.5)))
		if bossName then setText(bossName, p.name or "BOSS") end -- "<ranga> <nazwa>" z serwera (np. General Skibidi)
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

	-- staleness: boss przestał słać HP (śmierć bez czyszczenia fali) -> schowaj po ~0.5s
	RunService.Heartbeat:Connect(function()
		if bossBar.Visible and os.clock() - _lastHP > 0.5 then
			hide()
		end
	end)
end

return BossController
