--!nonstrict
-- StarterPlayerScripts/Controllers/BossController.luau  (post-bramka task 5 — klient)
-- Prominentny pasek HP bossa u gory (styl "ender dragon"): pojawia sie na boss-fali (Net.BossHP),
-- znika po pokonaniu (Net.BossDefeated -> flourish) lub koncu fali (Net.WaveEnded) lub gdy boss
-- przestaje slac HP (smierc bez czyszczenia fali). Minimalny v1.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))

local BossController = {}

local _barBg, _fill, _label, _flourish
local _lastHP = 0

function BossController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_Boss"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 45
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	_label = Instance.new("TextLabel")
	_label.Size = UDim2.fromScale(0.6, 0.04); _label.Position = UDim2.fromScale(0.2, 0.03)
	_label.BackgroundTransparency = 1; _label.TextColor3 = Color3.fromRGB(230, 120, 255)
	_label.Font = Enum.Font.GothamBlack; _label.TextScaled = true; _label.Text = "BOSS"
	_label.Visible = false; _label.Parent = gui

	_barBg = Instance.new("Frame")
	_barBg.Size = UDim2.fromScale(0.6, 0.028); _barBg.Position = UDim2.fromScale(0.2, 0.075)
	_barBg.BackgroundColor3 = Color3.fromRGB(30, 10, 40); _barBg.BorderSizePixel = 0
	_barBg.Visible = false; _barBg.Parent = gui
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(180, 90, 220); stroke.Thickness = 2; stroke.Parent = _barBg

	_fill = Instance.new("Frame")
	_fill.Size = UDim2.fromScale(1, 1); _fill.BackgroundColor3 = Color3.fromRGB(200, 60, 240)
	_fill.BorderSizePixel = 0; _fill.Parent = _barBg

	_flourish = Instance.new("TextLabel")
	_flourish.Size = UDim2.fromScale(0.7, 0.1); _flourish.Position = UDim2.fromScale(0.15, 0.4)
	_flourish.BackgroundTransparency = 1; _flourish.TextColor3 = Color3.fromRGB(255, 220, 120)
	_flourish.Font = Enum.Font.GothamBlack; _flourish.TextScaled = true; _flourish.Text = "BOSS POKONANY!"
	_flourish.Visible = false; _flourish.Parent = gui

	local function showBar() _barBg.Visible = true; _label.Visible = true end
	local function hideBar() _barBg.Visible = false; _label.Visible = false end

	Net.get("BossHP").OnClientEvent:Connect(function(p)
		if not p or not p.maxHp or p.maxHp <= 0 then
			return
		end
		local frac = math.clamp(p.hp / p.maxHp, 0, 1)
		_fill.Size = UDim2.fromScale(frac, 1)
		_label.Text = ("BOSS   %d / %d"):format(math.max(0, math.floor(p.hp + 0.5)), math.floor(p.maxHp + 0.5))
		showBar()
		_lastHP = os.clock()
	end)

	Net.get("BossDefeated").OnClientEvent:Connect(function()
		hideBar()
		_flourish.Visible = true
		task.delay(2.5, function()
			if _flourish then _flourish.Visible = false end
		end)
	end)

	Net.get("WaveEnded").OnClientEvent:Connect(function()
		hideBar() -- np. CoreDestroyed / boss dotarl do rdzenia
	end)

	-- staleness: boss przestal slac HP (smierc bez czyszczenia fali) -> schowaj po ~0.5s
	RunService.Heartbeat:Connect(function()
		if _barBg.Visible and os.clock() - _lastHP > 0.5 then
			hideBar()
		end
	end)
end

return BossController
