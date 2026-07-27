--!nonstrict
-- StarterPlayerScripts/Controllers/SkillTreeController.luau
-- Drzewko umiejetnosci na packu NodeTree — DOMYSLNY wyglad i zachowanie packa (reveal po zakupie).
-- Sekcje: LUCK / COMBAT / DEFEND / DICE UPDATE (nazwy w SkillTreeLayout). Pack sam renderuje wezly.
-- Ekonomia + efekty = serwer (SkillService): klik "<skillId>#<rank>" -> SkillPurchase(skillId) (RF).
-- Nasze: HUD "Umiejetnosci" toggle, naglowek (pasek postepu X/Y + salda z ikonami na zywo), Zamknij,
--   nawigacja (scroll zoom = pack, RMB trzymany = pan), polprzezroczyste tlo. Sync odporny na desync.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local SkillConfig = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("SkillConfig"))
local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums")).Currency

local SkillTreeController = {}

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

	local ownedIds: { [string]: boolean } = {}
	local totalRankNodes = 0
	for id in pairs(nodes) do
		if string.find(id, "#", 1, true) then
			totalRankNodes += 1
		end
	end
	local coins, rolls = 0, 0

	-- WR: badge przy Skills = ile umiejetnosci gracz moze TERAZ kupic (prereq spelniony + stac + niekupione)
	local function skillBadgeCount(): number
		local cnt = 0
		for id, node in pairs(SkillConfig.nodes) do
			if not ownedIds[id .. "#1"] then
				local prereqOk = true
				if node.prereqs then
					for reqId in pairs(node.prereqs) do
						if not ownedIds[reqId .. "#1"] then prereqOk = false break end
					end
				end
				if prereqOk then
					local bal = (node.currency == C.Coins) and coins or rolls
					if bal >= (node.base or 0) then cnt += 1 end
				end
			end
		end
		return cnt
	end
	local function updateSkillBadge()
		local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
		local sb = pg and pg:FindFirstChild("SideButtons")
		local bc = sb and sb:FindFirstChild("BottomCanvas")
		local btns = bc and bc:FindFirstChild("Buttons")
		local skills = btns and btns:FindFirstChild("Skills")
		local notify = skills and skills:FindFirstChild("Notify")
		if not notify then return end
		local n = skillBadgeCount()
		local lbl = notify:FindFirstChild("Text")
		if lbl and lbl:IsA("TextLabel") then lbl.Text = tostring(n) end
		notify.Visible = n > 0
	end

	-- ── naglowek + zamknij (osobne GUI nad drzewkiem) ──
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_SkillTreeHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- naglowek jak na obrazku (liczbys.png): pasek postepu + salda z ikonami z Offline Earnings
	local COIN_ICON = "rbxassetid://79510076315488"
	local DICE_ICON = "rbxassetid://83517758689278"

	local header = Instance.new("Frame")
	header.Size = UDim2.fromOffset(460, 96)
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.new(0.5, 0, 0, 46)
	header.BackgroundTransparency = 1 -- bez ciemnego pudelka
	header.BorderSizePixel = 0
	header.Visible = false
	header.Parent = gui

	-- pasek: posiadane / max umiejetnosci
	local barBG = Instance.new("Frame")
	barBG.Size = UDim2.fromOffset(300, 28); barBG.AnchorPoint = Vector2.new(0.5, 0)
	barBG.Position = UDim2.new(0.5, 0, 0, 0)
	barBG.BackgroundColor3 = Color3.fromRGB(18, 20, 28); barBG.BorderSizePixel = 0; barBG.Parent = header
	local bbc = Instance.new("UICorner"); bbc.CornerRadius = UDim.new(1, 0); bbc.Parent = barBG
	local bbs = Instance.new("UIStroke"); bbs.Color = Color3.fromRGB(8, 10, 16); bbs.Thickness = 2; bbs.Parent = barBG
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(0, 0, 1, 0); barFill.BackgroundColor3 = Color3.fromRGB(70, 150, 255)
	barFill.BorderSizePixel = 0; barFill.Parent = barBG
	local bfc = Instance.new("UICorner"); bfc.CornerRadius = UDim.new(1, 0); bfc.Parent = barFill
	local bfg = Instance.new("UIGradient")
	bfg.Color = ColorSequence.new(Color3.fromRGB(130, 205, 255), Color3.fromRGB(45, 120, 235))
	bfg.Rotation = 90; bfg.Parent = barFill
	local progL = Instance.new("TextLabel")
	progL.Size = UDim2.fromScale(1, 1); progL.BackgroundTransparency = 1
	progL.Font = Enum.Font.GothamBold; progL.TextSize = 18; progL.TextColor3 = Color3.new(1, 1, 1)
	progL.Text = "0/0"; progL.ZIndex = 2; progL.Parent = barBG
	local pls = Instance.new("UIStroke"); pls.Color = Color3.fromRGB(14, 16, 22); pls.Thickness = 2.2; pls.Parent = progL

	-- wiersz sald: [moneta] kwota    [kostka] kwota
	local row = Instance.new("Frame")
	row.Size = UDim2.fromOffset(460, 52); row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 40); row.BackgroundTransparency = 1; row.Parent = header
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal; rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rl.VerticalAlignment = Enum.VerticalAlignment.Center; rl.Padding = UDim.new(0, 8)
	rl.SortOrder = Enum.SortOrder.LayoutOrder; rl.Parent = row
	local function mkIcon(img, order)
		local ic = Instance.new("ImageLabel")
		ic.Size = UDim2.fromOffset(42, 42); ic.BackgroundTransparency = 1; ic.Image = img
		ic.LayoutOrder = order; ic.Parent = row
	end
	local function mkAmt(order)
		local l = Instance.new("TextLabel")
		l.AutomaticSize = Enum.AutomaticSize.X; l.Size = UDim2.fromOffset(0, 46)
		l.BackgroundTransparency = 1; l.Font = Enum.Font.GothamBold; l.TextSize = 30
		l.TextColor3 = Color3.new(1, 1, 1); l.Text = "0"; l.LayoutOrder = order; l.Parent = row
		local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(14, 16, 22); s.Thickness = 2.6; s.Parent = l
		return l
	end
	mkIcon(COIN_ICON, 1)
	local coinsL = mkAmt(2)
	local gap = Instance.new("Frame"); gap.Size = UDim2.fromOffset(28, 1); gap.BackgroundTransparency = 1; gap.LayoutOrder = 3; gap.Parent = row
	mkIcon(DICE_ICON, 4)
	local rollsL = mkAmt(5)

	local function refreshHeader()
		local owned = 0
		for _ in pairs(ownedIds) do
			owned += 1
		end
		progL.Text = ("%d/%d"):format(owned, totalRankNodes)
		local frac = totalRankNodes > 0 and (owned / totalRankNodes) or 0
		barFill.Size = UDim2.new(frac, 0, 1, 0)
		coinsL.Text = fmt(coins)
		rollsL.Text = fmt(rolls)
		-- WR: przekaz salda do packa -> ceny wezlow na czerwono gdy nie stac (pack koloruje gdy drzewo otwarte)
		pcall(function()
			if NodeTreeClient.setBalances then NodeTreeClient.setBalances(coins, rolls) end
		end)
		updateSkillBadge() -- WR: badge Skills = ile mozna teraz kupic
	end

	local function markOwned(id: string)
		if nodes[id] and not ownedIds[id] then
			ownedIds[id] = true
			NodeTreeClient.setIsNodeOwned(id, true)
			refreshHeader()
		end
	end

	-- galezie "owned" -> pack pokazuje rank1 (reveal packa: dziecko widoczne gdy rodzic owned)
	local function ownBranches()
		NodeTreeClient.setIsNodeOwned("root", true) -- root owned -> 3 dzieci REALNE (ich dzieci = "?", reszta ukryta)
		for id in pairs(nodes) do
			if string.sub(id, 1, 2) == "b:" then
				NodeTreeClient.setIsNodeOwned(id, true)
			end
		end
	end
	ownBranches()

	-- sync posiadanych rankow z serwera (idempotentne; server = zrodlo prawdy). Start + otwarcie.
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

	-- zakup na klik (serwer waliduje); self-heal: oznacz 1..resp.rank (odporne na desync)
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
				if okc and resp and resp.ok and resp.rank then
					for k = 1, resp.rank do
						markOwned(skillId .. "#" .. k)
					end
				end
			end)
		end
	end

	-- NOWE drzewo (ids bez "#"): klik = ODSLONIECIE dzieci (client-side, na razie bez kosztu; buy-cost dojdzie potem)
	for nodeId in pairs(nodes) do
		if nodeId ~= "root" and not string.find(nodeId, "#", 1, true) then
			NodeTreeClient.setPressedCallback(nodeId, function()
				markOwned(nodeId)
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

	-- DEV wyczyscil skille -> odznacz w packu + zwin drzewko
	Net.get("SkillTreeReset").OnClientEvent:Connect(function()
		for id in pairs(ownedIds) do
			NodeTreeClient.setIsNodeOwned(id, false)
		end
		table.clear(ownedIds)
		ownBranches()
		refreshHeader()
	end)

	-- ── przycisk HUD "Umiejetnosci" ──
	local openBtn = Instance.new("TextButton")
	openBtn.Size = UDim2.fromOffset(150, 54); openBtn.AnchorPoint = Vector2.new(0, 1)
	openBtn.Position = UDim2.new(0.5, 130, 1, -32)
	openBtn.BackgroundColor3 = Color3.fromRGB(88, 60, 140); openBtn.TextColor3 = Color3.new(1, 1, 1)
	openBtn.Font = Enum.Font.GothamBold; openBtn.TextSize = 15; openBtn.Text = "🌳 Umiejętności"
	openBtn.Parent = gui
	local oc = Instance.new("UICorner"); oc.CornerRadius = UDim.new(0, 10); oc.Parent = openBtn

	-- Zamknij: dol-srodek (jak na calyw.png)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(220, 58); closeBtn.AnchorPoint = Vector2.new(0.5, 1)
	closeBtn.Position = UDim2.new(0.5, 0, 1, -20)
	closeBtn.BackgroundColor3 = Color3.fromRGB(222, 60, 60); closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 24; closeBtn.Text = "Zamknij"
	closeBtn.Visible = false
	closeBtn.Parent = gui
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 12); cc.Parent = closeBtn
	local cst = Instance.new("UIStroke"); cst.Color = Color3.fromRGB(120, 22, 22); cst.Thickness = 3; cst.Parent = closeBtn

	local function doToggle()
		local willOpen = not NodeTreeClient.isTreeVisible()
		if willOpen then
			syncOwned()
		end
		NodeTreeClient.setIsTreeVisible(willOpen)
		if willOpen then
			refreshHeader() -- po otwarciu koloruj ceny wg sald (nie stac -> czerwony)
		end
	end
	SkillTreeController.Toggle = doToggle -- HUD ziomka (SideButtons.Skills) wola to
	openBtn.Visible = false -- stary temp guzik ukryty; logika drzewka zostaje
	openBtn.MouseButton1Click:Connect(doToggle)
	closeBtn.MouseButton1Click:Connect(function()
		NodeTreeClient.setIsTreeVisible(false)
	end)

	-- ── nawigacja: scroll = zoom (pack), RMB trzymany = pan; polprzezroczyste tlo ──
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local ntGui = playerGui:WaitForChild("NodeTreeGui")
	local mainFrame = ntGui:WaitForChild("MainFrame")
	local panning = false
	local lastMouse = Vector2.zero

	-- modal: przy otwartym drzewku chowamy CALE inne UI (zostaje drzewko + naglowek + Zamknij)
	local hiddenGuis = {}
	local function setHudHidden(hidden)
		if hidden then
			table.clear(hiddenGuis)
			for _, g in ipairs(playerGui:GetChildren()) do
				if g:IsA("ScreenGui") and g ~= gui and g ~= ntGui and g.Enabled then
					g.Enabled = false
					table.insert(hiddenGuis, g)
				end
			end
		else
			for _, g in ipairs(hiddenGuis) do
				if g and g.Parent then
					g.Enabled = true
				end
			end
			table.clear(hiddenGuis)
		end
	end

	-- WR: tryb umiejetnosci = tylko drzewo. Wylacz sterowanie postacia (ruch); tlo drzewa pochlania klik.
	local Controls
	local savedWS = 16
	pcall(function()
		Controls = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
	end)

	NodeTreeClient.treeVisibilityChanged:Connect(function(isVisible)
		header.Visible = isVisible
		closeBtn.Visible = isVisible
		openBtn.Visible = false -- temp guzik "Umiejetnosci" ZAWSZE ukryty (otwiera przycisk Skills ziomka w HUD)
		setHudHidden(isVisible)
		if isVisible then
			if Controls then Controls:Disable() end -- STOP ruchu postaci w trybie umiejetnosci
			local bf0 = ntGui:FindFirstChild("BackgroundFrame")
			if bf0 then bf0.Active = true end -- pochlaniaj klik w tlo (nie leci na plansze/postac)
			-- MODAL: pelnoekranowy TextButton pod wezlami. Frame+Active NIE daje gameProcessedEvent,
			-- dopiero GuiButton pochlania klik (gp=true) i zeruje Mouse.Target -> plansza/swiat nie lapie.
			local block = ntGui:FindFirstChild("WR_ClickBlock")
			if not block then
				block = Instance.new("TextButton")
				block.Name = "WR_ClickBlock"
				block.Size = UDim2.fromScale(1, 1)
				block.BackgroundTransparency = 1
				block.Text = ""
				block.AutoButtonColor = false
				block.ZIndex = 1 -- pod MainFrame (ZIndex 2) -> wezly dalej klikalne
				block.Active = true
				block.Selectable = false
				block.Parent = ntGui
			end
			block.Visible = true
			local hum0 = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
			if hum0 then savedWS = hum0.WalkSpeed; hum0.WalkSpeed = 0 end -- 100% stop ruchu (fallback gdyby controls nie zlapaly)
			task.delay(0.35, function()
				local bf = ntGui:FindFirstChild("BackgroundFrame")
				if bf and NodeTreeClient.isTreeVisible() then
					bf.Transparency = 0.45
				end
			end)
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
			if Controls then Controls:Enable() end -- przywroc sterowanie po zamknieciu drzewa
			local hum1 = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
			if hum1 then hum1.WalkSpeed = savedWS end -- przywroc predkosc chodu
			local block = ntGui:FindFirstChild("WR_ClickBlock")
			if block then block.Visible = false end -- zdejmij modal-blocker
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
