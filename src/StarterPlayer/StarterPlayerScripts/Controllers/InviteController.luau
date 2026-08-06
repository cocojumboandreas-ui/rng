--!nonstrict
-- StarterPlayerScripts/Controllers/InviteController.luau  (KLIENT)
-- Guzik "Invite Friends": widoczny gdy gracz ma Friends' Luck (n74+). Klik -> SocialService:PromptGameInvite.
-- Sciaga kolegow -> po wejsciu licza sie jako ZNAJOMI na serwerze -> +luck (patrz RollService.friendsLuckMult).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local InviteController = {}
local FRIEND_NODES = { "n74", "n99", "n100", "n101", "n102", "n103" }

function InviteController.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_Invite"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 500 -- nad przyciskami bocznymi (SideButtons), pod rewealem (1000)
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Styl spojny z HUD designera (wzorzec: SideButtons StartWave — zielony pionowy gradient + ciemny obrys).
	local btn = Instance.new("TextButton")
	btn.Name = "InviteBtn"
	btn.AnchorPoint = Vector2.new(0, 0.5)
	btn.Position = UDim2.new(0, 16, 0.74, 0) -- lewa krawedz, luka pod Index nad Offline Earnings
	btn.Size = UDim2.fromOffset(190, 54)
	btn.BackgroundColor3 = Color3.fromRGB(64, 178, 92)
	btn.AutoButtonColor = true
	btn.Text = "🎁 Invite Friends"
	btn.Font = Enum.Font.FredokaOne -- chunky, zaokraglony font jak etykiety designera
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextSize = 21
	btn.Visible = false
	btn.ZIndex = 60
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = btn
	-- pionowy gradient zieleni (jasniej u gory -> ciemniej u dolu), jak StartWave
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(122, 226, 142)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(74, 190, 102)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(48, 150, 78)),
	})
	grad.Parent = btn
	-- ciemny obrys krawedzi pigulki (near-black, idiom designera 0.106)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(27, 27, 27)
	stroke.Thickness = 2.5
	stroke.Parent = btn
	-- ciemny obrys TEKSTU dla czytelnosci (osobny label z ApplyStrokeMode=Contextual)
	local textStroke = Instance.new("UIStroke")
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Color = Color3.fromRGB(27, 27, 27)
	textStroke.Thickness = 1.6
	local textHolder = Instance.new("TextLabel")
	textHolder.Name = "Label"
	textHolder.BackgroundTransparency = 1
	textHolder.Size = UDim2.fromScale(1, 1)
	textHolder.Font = btn.Font
	textHolder.Text = btn.Text
	textHolder.TextColor3 = btn.TextColor3
	textHolder.TextSize = btn.TextSize
	textHolder.ZIndex = 61
	textStroke.Parent = textHolder
	textHolder.Parent = btn
	btn.Text = "" -- tekst rysuje label z obrysem
	btn.Parent = gui

	btn.Activated:Connect(function()
		-- PromptGameInvite WPROST. Per-klik CanSendGameInviteAsync bywa NIERZETELNY:
		-- potrafi zwrocic false albo wisiec 5s+ (web-call) -> przycisk "nie dziala jak klikam".
		-- Prompt sam grzecznie no-opuje gdy zaproszenia niedostepne, wiec gate jest zbedny.
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	end)

	-- pokaz guzik gdy gracz ma JAKIKOLWIEK wezel Friends' Luck (poll co 4s; kupno w drzewku bez broadcastu)
	task.spawn(function()
		while true do
			local ok, st = pcall(function()
				return Net.get("GetSkillState"):InvokeServer()
			end)
			local owns = false
			if ok and st and st.ranks then
				for _, node in ipairs(FRIEND_NODES) do
					if (st.ranks[node] or 0) > 0 then
						owns = true
						break
					end
				end
			end
			btn.Visible = owns
			task.wait(owns and 15 or 4)
		end
	end)
end

return InviteController
