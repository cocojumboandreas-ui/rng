--!nonstrict
-- StarterPlayerScripts/Controllers/WaveFxController.luau  (KLIENT)
-- Konfetti po WYCZYSZCZENIU fali. Net.WaveEnded leci TYLKO przy Cleared (pad bazy/stop -> RunSummary),
-- wiec kazdy WaveEnded = wygrana fala -> burst konfetti + krotki baner "WAVE CLEARED".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local WaveFxController = {}
local LP = Players.LocalPlayer

local COLORS = {
	Color3.fromRGB(255, 90, 90), Color3.fromRGB(90, 200, 255), Color3.fromRGB(255, 215, 90),
	Color3.fromRGB(120, 255, 130), Color3.fromRGB(230, 120, 255), Color3.fromRGB(255, 160, 60),
}

function WaveFxController.start()
	local pg = LP:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_WaveFx"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 400; gui.Parent = pg -- nad HUD, pod panelem ustawien

	-- baner "WAVE CLEARED"
	local banner = Instance.new("TextLabel")
	banner.AnchorPoint = Vector2.new(0.5, 0); banner.Position = UDim2.new(0.5, 0, 0.16, 0)
	banner.Size = UDim2.fromOffset(360, 56); banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.GothamBlack; banner.TextSize = 40; banner.TextColor3 = Color3.fromRGB(255, 235, 120)
	banner.TextStrokeColor3 = Color3.new(0, 0, 0); banner.TextStrokeTransparency = 0.3
	banner.Text = "WAVE CLEARED!"; banner.TextTransparency = 1; banner.Parent = gui

		-- gold popup "+N Monet" (nagroda za falę) — scale-in + float up
		local coinPop = Instance.new("TextLabel")
		coinPop.AnchorPoint = Vector2.new(0.5, 0); coinPop.Position = UDim2.new(0.5, 0, 0.26, 0)
		coinPop.Size = UDim2.fromOffset(320, 46); coinPop.BackgroundTransparency = 1
		coinPop.Font = Enum.Font.GothamBlack; coinPop.TextSize = 34; coinPop.TextColor3 = Color3.fromRGB(255, 210, 70)
		coinPop.TextStrokeColor3 = Color3.new(0, 0, 0); coinPop.TextStrokeTransparency = 0.25
		coinPop.Text = ""; coinPop.TextTransparency = 1; coinPop.Parent = gui

		local function shortCoins(n)
			n = math.max(0, math.floor(n + 0.5))
			if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
			if n >= 1000 then return string.format("%.1fK", n / 1000) end
			return tostring(n)
		end

		local function showCoins(amount)
			if not amount or amount <= 0 then return end
			coinPop.Text = "+" .. shortCoins(amount) .. " Coins"
			coinPop.TextTransparency = 1; coinPop.TextStrokeTransparency = 1
			coinPop.TextSize = 22; coinPop.Position = UDim2.new(0.5, 0, 0.27, 0)
			TweenService:Create(coinPop, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				TextTransparency = 0, TextStrokeTransparency = 0.25, TextSize = 34, Position = UDim2.new(0.5, 0, 0.24, 0),
			}):Play()
			task.delay(1.3, function()
				TweenService:Create(coinPop, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.new(0.5, 0, 0.21, 0) }):Play()
			end)
		end

		-- ambient: unoszace sie zielone koniczyny szczescia (echo "+szczescia" z gry-wzorca)
		local CLOVER = Color3.fromRGB(120, 255, 130)
		local function cloverRise()
			for _ = 1, 14 do
				local pc = Instance.new("Frame")
				local sz = math.random(10, 20)
				pc.Size = UDim2.fromOffset(sz, sz); pc.BackgroundColor3 = CLOVER; pc.BorderSizePixel = 0
				pc.Rotation = math.random(0, 360); pc.BackgroundTransparency = 0.15
				pc.Position = UDim2.new(0.28 + math.random() * 0.44, 0, 0.62 + math.random() * 0.12, 0); pc.Parent = gui
				local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0.5, 0); cc.Parent = pc
				local dur = 1.1 + math.random() * 0.8
				TweenService:Create(pc, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.new(pc.Position.X.Scale, 0, 0.30 + math.random() * 0.12, 0),
					BackgroundTransparency = 1, Rotation = pc.Rotation + math.random(-180, 180),
				}):Play()
				Debris:AddItem(pc, dur + 0.2)
			end
		end

	local function showBanner()
		banner.TextTransparency = 1; banner.TextStrokeTransparency = 1
		banner.Position = UDim2.new(0.5, 0, 0.13, 0)
		TweenService:Create(banner, TweenInfo.new(0.25), { TextTransparency = 0, TextStrokeTransparency = 0.3, Position = UDim2.new(0.5, 0, 0.16, 0) }):Play()
		task.delay(1.4, function()
			TweenService:Create(banner, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end)
	end

	local function burst()
		for i = 1, 70 do
			local p = Instance.new("Frame")
			local sz = math.random(8, 16)
			p.Size = UDim2.fromOffset(sz, sz * (math.random() < 0.5 and 1 or 0.5))
			local startX = math.random()
			p.Position = UDim2.new(startX, 0, -0.05 - math.random() * 0.1, 0)
			p.BackgroundColor3 = COLORS[math.random(#COLORS)]
			p.Rotation = math.random(0, 360); p.BorderSizePixel = 0; p.Parent = gui
			local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 2); corner.Parent = p
			local fallT = 1.6 + math.random() * 1.4
			local endX = math.clamp(startX + (math.random() - 0.5) * 0.2, 0, 1)
			TweenService:Create(p, TweenInfo.new(fallT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(endX, 0, 1.15, 0), Rotation = p.Rotation + math.random(-540, 540),
			}):Play()
			task.delay(fallT - 0.35, function()
				if p.Parent then TweenService:Create(p, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play() end
			end)
			Debris:AddItem(p, fallT + 0.5)
		end
	end

	Net.get("WaveEnded").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			burst()
			showBanner()
			cloverRise()
			showCoins(payload.summary and payload.summary.coinsEarned)
		end
	end)
end

return WaveFxController
