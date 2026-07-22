--!nonstrict
-- StarterPlayerScripts/Controllers/SkillTreeController.luau
-- Drzewko umiejetnosci na packu NodeTree (ReplicatedStorage.NodeTree), wpiete w nasz SkillService.
-- Pack = tylko wizual (owned/nie, layout z SkillTreeLayout). Ekonomia + efekty = serwer:
--   klik wezla "<skillId>#<rank>" -> SkillPurchase(skillId) (RF) -> ok -> setIsNodeOwned(true).
-- Stan poczatkowy: GetSkillState (RF) -> oznacz posiadane ranki. HUD "SKILLE" toggluje widocznosc.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))

local SkillTreeController = {}

-- "<skillId>#<rank>" -> skillId, rank ; inne id (root / b:*) -> nil
local function parseNodeId(nodeId: string)
	local hash = string.find(nodeId, "#", 1, true)
	if not hash then
		return nil, nil
	end
	local skillId = string.sub(nodeId, 1, hash - 1)
	local rank = tonumber(string.sub(nodeId, hash + 1))
	return skillId, rank
end

function SkillTreeController.start()
	local NodeTree = ReplicatedStorage:WaitForChild("NodeTree", 30)
	if not NodeTree then
		warn("[SkillTreeController] Brak ReplicatedStorage.NodeTree — drzewko nie wystartuje.")
		return
	end
	local NodeTreeClient = require(NodeTree:WaitForChild("NodeTreeClient"))
	local nodes = NodeTreeClient.getNodes()

	-- pack pokazuje drzewko od razu przy require -> schowaj do czasu klikniecia SKILLE
	NodeTreeClient.setIsTreeVisible(false)

	-- galezie (b:*) zawsze "posiadane" -> pierwsze ranki widoczne od startu
	for nodeId in pairs(nodes) do
		if string.sub(nodeId, 1, 2) == "b:" then
			NodeTreeClient.setIsNodeOwned(nodeId, true)
		end
	end

	-- wczytaj zapisane ranki -> oznacz posiadane wezly (rank 1..r)
	local ok, state = pcall(function()
		return Net.get("GetSkillState"):InvokeServer()
	end)
	local ranks = (ok and state and state.ranks) or {}
	for skillId, rank in pairs(ranks) do
		for k = 1, rank do
			local id = skillId .. "#" .. k
			if nodes[id] then
				NodeTreeClient.setIsNodeOwned(id, true)
			end
		end
	end

	-- zakup na klik (serwer waliduje koszt/kolejnosc/walute)
	for nodeId in pairs(nodes) do
		local skillId, rank = parseNodeId(nodeId)
		if skillId and rank then
			NodeTreeClient.setPressedCallback(nodeId, function()
				if NodeTreeClient.isNodeOwned(nodeId) then
					return -- juz kupione; nie kupuj przypadkiem nastepnego ranku
				end
				local resp
				local okc = pcall(function()
					resp = Net.get("SkillPurchase"):InvokeServer(skillId)
				end)
				if okc and resp and resp.ok and resp.rank == rank then
					NodeTreeClient.setIsNodeOwned(nodeId, true)
				end
			end)
		end
	end

	-- HUD "SKILLE" (mirror ZBUDUJ: dol-srodek, +130 z prawej) — toggle drzewka
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_SkillTreeToggle"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50 -- nad NodeTreeGui, zeby przycisk byl klikalny gdy drzewko otwarte
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local openBtn = Instance.new("TextButton")
	openBtn.Size = UDim2.fromOffset(140, 54)
	openBtn.AnchorPoint = Vector2.new(0, 1)
	openBtn.Position = UDim2.new(0.5, 130, 1, -32)
	openBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 90)
	openBtn.TextColor3 = Color3.new(1, 1, 1)
	openBtn.Font = Enum.Font.GothamBold
	openBtn.TextSize = 15
	openBtn.Text = "🌳 Umiejętności"
	openBtn.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = openBtn

	openBtn.MouseButton1Click:Connect(function()
		NodeTreeClient.setIsTreeVisible(not NodeTreeClient.isTreeVisible())
	end)

	-- ── nawigacja po drzewie: scroll = zoom (obsluguje pack), RMB trzymany = pan ──
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local ntGui = playerGui:WaitForChild("NodeTreeGui")
	local mainFrame = ntGui:WaitForChild("MainFrame")

	local panning = false
	local lastMouse = Vector2.zero

	-- Gdy drzewko otwarte: sink RMB przez caly czas -> kamera sie nie obraca, RMB = pan.
	NodeTreeClient.treeVisibilityChanged:Connect(function(isVisible)
		if isVisible then
			ContextActionService:BindActionAtPriority(
				"WR_TreePanSink",
				function()
					return Enum.ContextActionResult.Sink
				end,
				false,
				Enum.ContextActionPriority.High.Value,
				Enum.UserInputType.MouseButton2
			)
		else
			panning = false
			ContextActionService:UnbindAction("WR_TreePanSink")
		end
	end)

	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and NodeTreeClient.isTreeVisible() then
			panning = true
			lastMouse = UserInputService:GetMouseLocation()
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if panning and input.UserInputType == Enum.UserInputType.MouseMovement then
			local m = UserInputService:GetMouseLocation()
			local delta = m - lastMouse
			lastMouse = m
			mainFrame.Position += UDim2.fromOffset(delta.X, delta.Y)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			panning = false
		end
	end)
end

return SkillTreeController
