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

	local btn = Instance.new("TextButton")
	btn.Name = "InviteBtn"
	btn.AnchorPoint = Vector2.new(0, 0.5)
	btn.Position = UDim2.new(0, 16, 0.74, 0) -- lewa krawedz, luka pod Index nad Offline Earnings
	btn.Size = UDim2.fromOffset(186, 52)
	btn.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
	btn.AutoButtonColor = true
	btn.Text = "🎁 Invite Friends"
	btn.Font = Enum.Font.GothamBlack
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextSize = 20
	btn.Visible = false
	btn.ZIndex = 60
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = btn
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 80, 40)
	stroke.Thickness = 2
	stroke.Parent = btn
	btn.Parent = gui

	btn.Activated:Connect(function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok and can then
			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		end
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
