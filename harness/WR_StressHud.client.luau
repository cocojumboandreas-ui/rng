--!nonstrict
-- WR_StressHud  (TYMCZASOWY — bramka Task 8; USUŃ po zielonej bramce)
-- Ekran: FPS (klient) + serwerowy tick [ms] + EnemySync [KB/s] (mierzony na kliencie) + przycisk START/STOP.
-- Cele bramki: FPS >= 30 (sredni telefon), tick < 8 ms, EnemySync < 15 KB/s na klienta.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local toggle = ReplicatedStorage:WaitForChild("WR_StressToggle")
local stats = ReplicatedStorage:WaitForChild("WR_StressStats")
local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local gui = Instance.new("ScreenGui")
gui.Name = "WR_StressHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(300, 96)
label.Position = UDim2.fromOffset(12, 12)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.25
label.TextColor3 = Color3.new(1, 1, 1)
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Font = Enum.Font.Code
label.TextSize = 16
label.Text = "STRESS: off"
label.Parent = gui

local btn = Instance.new("TextButton")
btn.Size = UDim2.fromOffset(300, 48)
btn.Position = UDim2.fromOffset(12, 116)
btn.BackgroundColor3 = Color3.fromRGB(40, 120, 40)
btn.TextColor3 = Color3.new(1, 1, 1)
btn.Font = Enum.Font.GothamBold
btn.TextSize = 18
btn.Text = "START STRESS"
btn.Parent = gui

local on = false
btn.MouseButton1Click:Connect(function()
	on = not on
	toggle:FireServer(on)
	btn.Text = on and "STOP STRESS" or "START STRESS"
	btn.BackgroundColor3 = on and Color3.fromRGB(150, 40, 40) or Color3.fromRGB(40, 120, 40)
end)

-- FPS
local frames, acc, fps = 0, 0, 0
RunService.RenderStepped:Connect(function(dt)
	frames += 1
	acc += dt
	if acc >= 0.5 then
		fps = math.floor(frames / acc + 0.5)
		frames, acc = 0, 0
	end
end)

-- serwerowy tick z broadcastu
local srvTick = 0
stats.OnClientEvent:Connect(function(s)
	srvTick = s.tickMs
end)

-- EnemySync KB/s mierzony na KLIENCIE (bajty odebrane)
local rxBytes, rxKBps = 0, 0
Net.get("EnemySync").OnClientEvent:Connect(function(_plotId, buf)
	if type(buf) == "buffer" then
		rxBytes += buffer.len(buf)
	end
end)
task.spawn(function()
	while true do
		task.wait(1)
		rxKBps = rxBytes / 1024
		rxBytes = 0
	end
end)

RunService.Heartbeat:Connect(function()
	label.Text = string.format(
		"STRESS %s\nFPS: %d  (cel >=30)\nserwer tick: %.2f ms  (cel <8)\nEnemySync: %.1f KB/s  (cel <15)",
		on and "ON" or "off", fps, srvTick, rxKBps
	)
end)
