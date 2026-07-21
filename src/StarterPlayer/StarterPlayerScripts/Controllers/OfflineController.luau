--!nonstrict
-- StarterPlayerScripts/Controllers/OfflineController.luau  (post-bramka task 3 — klient)
-- Popup "Witaj z powrotem — zarobiles X monet przez Yh Zm" na dolaczeniu (AUTO-SHOW, bez przycisku,
-- auto-znika po ~6s). Sluchamy Net.OfflineEarnings (S->C {coins, seconds}). Minimalny.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))

local OfflineController = {}

local function fmtDuration(seconds: number): string
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h > 0 then
		return h .. "h " .. m .. "m"
	end
	return m .. "m"
end

function OfflineController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_Offline"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(360, 92); frame.Position = UDim2.fromScale(0.5, 0.18)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(25, 30, 40); frame.BorderSizePixel = 0
	frame.Visible = false; frame.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 26); title.Position = UDim2.fromOffset(8, 8)
	title.BackgroundTransparency = 1; title.TextColor3 = Color3.fromRGB(255, 220, 120)
	title.Font = Enum.Font.GothamBold; title.TextSize = 18; title.Text = "Witaj z powrotem!"
	title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = frame

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -16, 0, 46); body.Position = UDim2.fromOffset(8, 38)
	body.BackgroundTransparency = 1; body.TextColor3 = Color3.new(1, 1, 1)
	body.Font = Enum.Font.Gotham; body.TextSize = 15; body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left; body.TextYAlignment = Enum.TextYAlignment.Top
	body.Text = ""; body.Parent = frame

	Net.get("OfflineEarnings").OnClientEvent:Connect(function(p)
		if not p or not p.coins or p.coins <= 0 then
			return
		end
		body.Text = ("Zarobiles %d monet przez %s (offline)."):format(p.coins, fmtDuration(p.seconds or 0))
		frame.Visible = true
		task.delay(6, function()
			if frame then
				frame.Visible = false
			end
		end)
	end)
end

return OfflineController
