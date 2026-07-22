--!nonstrict
-- StarterPlayerScripts/Controllers/SkillTreeController.luau
-- Drzewko umiejetnosci na packu NodeTree (ReplicatedStorage.NodeTree), wpiete w nasz SkillService.
-- Pack = tylko wizual (owned/nie, layout z SkillTreeLayout). Ekonomia + efekty = serwer:
--   klik wezla "<skillId>#<rank>" -> SkillPurchase(skillId) (RF) -> ok -> setIsNodeOwned(true).
-- Warstwa nasza (git): HUD "Umiejetnosci" toggle, naglowek (postep X/Y + salda 🪙/🎲 na zywo),
--   Zamknij, nawigacja (scroll zoom = pack, RMB trzymany = pan), KOLORY body (bialy hex + tint
--   per galaz), "?" na zablokowanych (pack pokazuje wszystko, controller styluje), tooltipy.
-- Sync odporny na desync: self-heal po zakupie (oznacz 1..resp.rank) + re-sync przy otwarciu.
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
	return string.sub(nodeId, 1, hash - 1), tonumber(string.sub(nodeId, hash + 1))
end

local function fmt(n: number?): string
	n = n or 0
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

function SkillTreeController.start()
	local NodeTree = ReplicatedStorage:WaitForChild("NodeTree", 30)
	if not NodeTree then
		warn("[SkillTreeController] Brak ReplicatedStorage.NodeTree — drzewko nie wystartuje.")
		return
	end
	local NodeTreeClient = require(NodeTree:WaitForChild("NodeTreeClient"))
	local nodes = NodeTreeClient.getNodes()

	NodeTreeClient.setIsTreeVisible(false)

	-- stan: posiadane wezly rankowe / total
	local ownedIds: { [string]: boolean } = {}
	local totalRankNodes = 0
	for id in pairs(nodes) do
		if string.find(id, "#", 1, true) then
			totalRankNodes += 1
		end
	end
	local coins, rolls = 0, 0
	local restyle -- forward decl; przypisany po zbudowaniu mapy instancji wezlow

	-- ── naglowek + zamknij (osobne GUI nad drzewkiem) ──
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_SkillTreeHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50 -- nad NodeTreeGui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- naglowek (gora-srodek): pasek postepu + X/Y + salda
	local header = Instance.new("Frame")
	header.Size = UDim2.fromOffset(320, 64)
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.new(0.5, 0, 0, 10)
	header.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
	header.BackgroundTransparency = 0.1
	header.BorderSizePixel = 0
	header.Visible = false
	header.Parent = gui
	local hcorner = Instance.new("UICorner"); hcorner.CornerRadius = UDim.new(0, 12); hcorner.Parent = header

	local barBG = Instance.new("Frame")
	barBG.Size = UDim2.new(1, -24, 0, 8); barBG.Position = UDim2.fromOffset(12, 10)
	barBG.BackgroundColor3 = Color3.fromRGB(45, 45, 60); barBG.BorderSizePixel = 0; barBG.Parent = header
	local bbc = Instance.new("UICorner"); bbc.CornerRadius = UDim.new(1, 0); bbc.Parent = barBG
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(0, 0, 1, 0); barFill.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
	barFill.BorderSizePixel = 0; barFill.Parent = barBG
	local bfc = Instance.new("UICorner"); bfc.CornerRadius = UDim.new(1, 0); bfc.Parent = barFill

	local function mkLabel(parent, size, pos, txt, color, xa)
		local l = Instance.new("TextLabel")
		l.Size = size; l.Position = pos; l.BackgroundTransparency = 1
		l.TextColor3 = color or Color3.new(1, 1, 1)
		l.Font = Enum.Font.GothamBold; l.TextSize = 16; l.Text = txt
		l.TextXAlignment = xa or Enum.TextXAlignment.Center
		l.Parent = parent
		return l
	end

	local progL = mkLabel(header, UDim2.fromOffset(120, 24), UDim2.fromOffset(12, 26), "0 / 0", Color3.fromRGB(200, 220, 255), Enum.TextXAlignment.Left)
	local coinsL = mkLabel(header, UDim2.fromOffset(95, 24), UDim2.new(1, -190, 0, 26), "🪙 0", Color3.fromRGB(255, 215, 90))
	local rollsL = mkLabel(header, UDim2.fromOffset(95, 24), UDim2.new(1, -95, 0, 26), "🎲 0", Color3.new(1, 1, 1))

	local function refreshHeader()
		local owned = 0
		for _ in pairs(ownedIds) do
			owned += 1
		end
		progL.Text = ("%d / %d"):format(owned, totalRankNodes)
		local frac = totalRankNodes > 0 and (owned / totalRankNodes) or 0
		barFill.Size = UDim2.new(frac, 0, 1, 0)
		coinsL.Text = "🪙 " .. fmt(coins)
		rollsL.Text = "🎲 " .. fmt(rolls)
	end

	local function markOwned(id: string)
		if nodes[id] and not ownedIds[id] then
			ownedIds[id] = true
			NodeTreeClient.setIsNodeOwned(id, true)
			refreshHeader()
			if restyle then
				restyle()
			end
		end
	end

	-- galezie zawsze "owned" (nie licza sie do postepu — to nie ranki)
	for id in pairs(nodes) do
		if string.sub(id, 1, 2) == "b:" then
			NodeTreeClient.setIsNodeOwned(id, true)
		end
	end

	-- sync posiadanych rankow z serwera (idempotentne; server = zrodlo prawdy, ranki tylko rosna).
	-- Wolane na starcie ORAZ przy kazdym otwarciu (leczy wyscig z ProfileLoaded i desync).
	local function syncOwned()
		local ok, state = pcall(function()
			return Net.get("GetSkillState"):InvokeServer()
		end)
		if ok and state then
			if state.coins ~= nil then
				coins = state.coins
			end
			if state.spendableRolls ~= nil then
				rolls = state.spendableRolls
			end
			for skillId, rank in pairs(state.ranks or {}) do
				for k = 1, rank do
					markOwned(skillId .. "#" .. k)
				end
			end
		end
		refreshHeader()
	end
	syncOwned()

	-- zakup na klik (serwer waliduje koszt/kolejnosc/walute)
	for nodeId in pairs(nodes) do
		local skillId, rank = parseNodeId(nodeId)
		if skillId and rank then
			NodeTreeClient.setPressedCallback(nodeId, function()
				if ownedIds[nodeId] then
					return
				end
				local resp
				local okc = pcall(function()
					resp = Net.get("SkillPurchase"):InvokeServer(skillId)
				end)
				-- self-heal: oznacz wszystkie ranki do serwerowego (odporne na desync klient<->serwer)
				if okc and resp and resp.ok and resp.rank then
					for k = 1, resp.rank do
						markOwned(skillId .. "#" .. k)
					end
				end
			end)
		end
	end

	-- salda na zywo
	Net.get("CoinsSync").OnClientEvent:Connect(function(p)
		if p and p.balance ~= nil then coins = p.balance; refreshHeader() end
	end)
	Net.get("RollsSync").OnClientEvent:Connect(function(p)
		if p and p.spendableRolls ~= nil then rolls = p.spendableRolls; refreshHeader() end
	end)

	-- DEV wyczyscil skille -> wyczysc lokalny stan posiadania + przemaluj drzewko
	Net.get("SkillTreeReset").OnClientEvent:Connect(function()
		table.clear(ownedIds)
		refreshHeader()
		if restyle then
			restyle()
		end
	end)

	-- ── przycisk HUD "Umiejetnosci" (mirror ZBUDUJ) ──
	local openBtn = Instance.new("TextButton")
	openBtn.Size = UDim2.fromOffset(150, 54); openBtn.AnchorPoint = Vector2.new(0, 1)
	openBtn.Position = UDim2.new(0.5, 130, 1, -32)
	openBtn.BackgroundColor3 = Color3.fromRGB(88, 60, 140); openBtn.TextColor3 = Color3.new(1, 1, 1)
	openBtn.Font = Enum.Font.GothamBold; openBtn.TextSize = 15; openBtn.Text = "🌳 Umiejętności"
	openBtn.Parent = gui
	local oc = Instance.new("UICorner"); oc.CornerRadius = UDim.new(0, 10); oc.Parent = openBtn

	-- ── przycisk Zamknij (gora-prawo) ──
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(120, 40); closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -16, 0, 16)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 55, 55); closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 16; closeBtn.Text = "✕ Zamknij"
	closeBtn.Visible = false
	closeBtn.Parent = gui
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = closeBtn

	openBtn.MouseButton1Click:Connect(function()
		local willOpen = not NodeTreeClient.isTreeVisible()
		if willOpen then
			syncOwned() -- odswiez posiadane ranki z serwera przy otwarciu
		end
		NodeTreeClient.setIsTreeVisible(willOpen)
	end)
	closeBtn.MouseButton1Click:Connect(function()
		NodeTreeClient.setIsTreeVisible(false)
	end)

	-- ── nawigacja: scroll = zoom (pack), RMB trzymany = pan ──
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local ntGui = playerGui:WaitForChild("NodeTreeGui")
	local mainFrame = ntGui:WaitForChild("MainFrame")

	-- ── kolory (bialy fill hex + tint per galaz), "?" zablokowane, tooltipy ──
	-- Mapowanie instancja->nodeId przez atrybut WR_NodeId (dodany w packu NodeTreeClient).
	local SkillConfig = require(ReplicatedStorage.Content.Config:WaitForChild("SkillConfig"))
	local FILL = "rbxassetid://72596611749182" -- bialy hex (playmakers) do tintowania
	local BRANCH_COLOR = {
		RNG = Color3.fromRGB(70, 205, 110),
		Eco = Color3.fromRGB(240, 195, 60),
		Combat = Color3.fromRGB(230, 75, 75),
		Base = Color3.fromRGB(70, 140, 240),
	}
	local ROOT_COLOR = Color3.fromRGB(150, 100, 235)
	local LOCK_COLOR = Color3.fromRGB(70, 74, 90)
	local STAT_LABEL = {
		luck = "szczescie", rollSpeed = "tempo rolki", mutChance = "szansa mutacji",
		cellBudget = "budzet cel", dmgMult = "obrazenia", fireRateMult = "szybkostrzelnosc",
		rangeMult = "zasieg", coreHP = "HP rdzenia", coinMult = "monety", offlineRate = "offline/h",
		variantLuck = "szansa wariantu",
	}
	local CUR_EMOJI = { Coins = "🪙", Rolls = "🎲" }

	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ FILL })
	end)

	-- tooltip (jeden, reuzywalny)
	local tip = Instance.new("Frame")
	tip.Size = UDim2.fromOffset(230, 58); tip.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
	tip.BackgroundTransparency = 0.05; tip.BorderSizePixel = 0; tip.Visible = false
	tip.ZIndex = 30; tip.Parent = gui
	local tipc = Instance.new("UICorner"); tipc.CornerRadius = UDim.new(0, 8); tipc.Parent = tip
	local tipName = mkLabel(tip, UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 6), "", Color3.new(1, 1, 1), Enum.TextXAlignment.Left)
	tipName.ZIndex = 31
	local tipDesc = Instance.new("TextLabel")
	tipDesc.Size = UDim2.new(1, -16, 0, 26); tipDesc.Position = UDim2.fromOffset(8, 28)
	tipDesc.BackgroundTransparency = 1; tipDesc.TextColor3 = Color3.fromRGB(200, 210, 230)
	tipDesc.Font = Enum.Font.Gotham; tipDesc.TextSize = 13; tipDesc.TextWrapped = true
	tipDesc.TextXAlignment = Enum.TextXAlignment.Left; tipDesc.TextYAlignment = Enum.TextYAlignment.Top
	tipDesc.ZIndex = 31; tipDesc.Parent = tip

	local function showTip(inst, skillId, rank)
		local sc = SkillConfig.nodes[skillId]
		if not sc then
			return
		end
		local cfg = nodes[skillId .. "#" .. rank]
		local cost = (cfg and cfg.price and cfg.price.quantity) or 0
		local sign = (sc.effect.perRank >= 0) and "+" or ""
		tipName.Text = ("%s  (rank %d)"):format(sc.label or skillId, rank)
		tipDesc.Text = ("%s%s %s/rank   •   %s %s"):format(
			sign, tostring(sc.effect.perRank), STAT_LABEL[sc.effect.stat] or sc.effect.stat,
			CUR_EMOJI[sc.currency] or "", fmt(cost)
		)
		local ap, asz = inst.AbsolutePosition, inst.AbsoluteSize
		tip.Position = UDim2.fromOffset(ap.X + asz.X + 6, ap.Y)
		tip.Visible = true
	end

	-- mapa instancja wezla po nodeId + podpiecie tooltipow
	local instById = {}
	for _, inst in ipairs(mainFrame:GetDescendants()) do
		local id = inst:GetAttribute("WR_NodeId")
		if id and inst:IsA("GuiButton") then
			instById[id] = inst
			local skillId, rank = parseNodeId(id)
			if skillId and rank then
				inst.MouseEnter:Connect(function()
					showTip(inst, skillId, rank)
				end)
				inst.MouseLeave:Connect(function()
					tip.Visible = false
				end)
			end
		end
	end

	-- wyglad jednego wezla: available = kolor galezi + tresc; locked = szary "?"
	local function styleNode(inst, id, available)
		local cfg = nodes[id]
		local bg = inst:FindFirstChild("Background")
		local bgIcon = bg and bg:FindFirstChild("Icon")
		if bgIcon then
			bgIcon.Image = FILL
			bgIcon.ImageColor3 = available and ((cfg and cfg.wrBranch and BRANCH_COLOR[cfg.wrBranch]) or ROOT_COLOR) or LOCK_COLOR
		end
		local mainIcon = inst:FindFirstChild("Icon")
		local ptext = inst:FindFirstChild("PrimaryText")
		local price = inst:FindFirstChild("Price")
		local hdr = inst:FindFirstChild("HeaderText")
		if available then
			if mainIcon then mainIcon.ImageTransparency = 0 end
			if price then price.Visible = true end
			if ptext then ptext.Text = (cfg and cfg.text) or "" end
			if hdr and cfg and cfg.headerText then hdr.Visible = true end
		else
			if mainIcon then mainIcon.ImageTransparency = 1 end
			if price then price.Visible = false end
			if ptext then ptext.Text = "?" end
			if hdr then hdr.Visible = false end
		end
	end

	-- available = kupione LUB nastepne do kupienia (poprzedni rank kupiony / rank1 / galaz-root)
	restyle = function()
		for id, inst in pairs(instById) do
			local skillId, rank = parseNodeId(id)
			local available
			if skillId and rank then
				available = ownedIds[id] or rank == 1 or ownedIds[skillId .. "#" .. (rank - 1)] == true
			else
				available = true
			end
			styleNode(inst, id, available)
		end
	end
	restyle()

	local panning = false
	local lastMouse = Vector2.zero

	NodeTreeClient.treeVisibilityChanged:Connect(function(isVisible)
		header.Visible = isVisible
		closeBtn.Visible = isVisible
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
			mainFrame.Position += UDim2.fromOffset((m - lastMouse).X, (m - lastMouse).Y)
			lastMouse = m
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			panning = false
		end
	end)
end

return SkillTreeController
