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
		end
	end)
end

return WaveFxController
