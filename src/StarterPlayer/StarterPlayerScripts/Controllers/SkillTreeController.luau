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
			if NodeTreeClient.refresh then
				NodeTreeClient.refresh() -- odkryj nowe wezly (frontier wzrosl)
			end
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

	-- salda na zywo (+ odswiez pulsy: zmiana kasy moze wlaczyc/wylaczyc "stac cie")
	Net.get("CoinsSync").OnClientEvent:Connect(function(p)
		if p and p.balance ~= nil then coins = p.balance; refreshHeader(); if restyle then restyle() end end
	end)
	Net.get("RollsSync").OnClientEvent:Connect(function(p)
		if p and p.spendableRolls ~= nil then rolls = p.spendableRolls; refreshHeader(); if restyle then restyle() end end
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

	-- ── kolory (szary=niekupione, niebieski=kupione), "?" zablokowane, pulsowanie, tooltip 3-sekcje ──
	-- Mapowanie instancja->nodeId przez atrybut WR_NodeId (dodany w packu NodeTreeClient).
	local TweenService = game:GetService("TweenService")
	local SkillConfig = require(ReplicatedStorage.Content.Config:WaitForChild("SkillConfig"))
	local FILL = "rbxassetid://72596611749182" -- bialy hex; tlo + obramowka (wiekszy hex za wezlem = rabek)
	local COL_OWNED = Color3.fromRGB(58, 120, 225) -- kupione = niebieskie
	local COL_UNOWNED = Color3.fromRGB(78, 82, 96) -- niekupione (available/"?") = szare
	local COL_BRANCH = Color3.fromRGB(80, 180, 90) -- galezie = zielone
	local COL_ROOT = Color3.fromRGB(215, 70, 70) -- root = czerwony
	local COL_PULSE = Color3.fromRGB(255, 240, 120) -- obramowka pulsu (stac cie)
	local LOOKAHEAD = 3 -- widoczne: frontier + 1 odkryta + 2 "?"
	local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII" }
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

	-- najwyzszy kupiony rank skilla (0 = nic)
	local function frontier(skillId)
		local sc = SkillConfig.nodes[skillId]
		local mx = sc and sc.maxRank or 0
		local f = 0
		for k = 1, mx do
			if ownedIds[skillId .. "#" .. k] then f = k else break end
		end
		return f
	end
	-- czy gracza stac na dany node (available)
	local function affordable(skillId, id)
		local sc = SkillConfig.nodes[skillId]
		local cfg = nodes[id]
		local cost = (cfg and cfg.price and cfg.price.quantity) or 0
		local bal = (sc and sc.currency == "Rolls") and rolls or coins
		return bal >= cost
	end

	-- ── tooltip 3-sekcyjny (nazwa / efekt / status) — wzor og.png ──
	local tip = Instance.new("Frame")
	tip.Size = UDim2.fromOffset(248, 96); tip.BackgroundColor3 = Color3.fromRGB(214, 222, 236)
	tip.BackgroundTransparency = 0.03; tip.BorderSizePixel = 0; tip.Visible = false
	tip.ZIndex = 30; tip.Parent = gui
	local tipc = Instance.new("UICorner"); tipc.CornerRadius = UDim.new(0, 12); tipc.Parent = tip
	local tipName = mkLabel(tip, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 8), "", Color3.fromRGB(22, 26, 38))
	tipName.TextSize = 19; tipName.ZIndex = 31
	local tipDesc = mkLabel(tip, UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 38), "", Color3.fromRGB(45, 55, 75))
	tipDesc.TextSize = 14; tipDesc.Font = Enum.Font.Gotham; tipDesc.ZIndex = 31
	local tipStatus = mkLabel(tip, UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 64), "", Color3.fromRGB(60, 165, 70))
	tipStatus.TextSize = 16; tipStatus.ZIndex = 31

	local function showTip(inst, skillId, rank)
		local sc = SkillConfig.nodes[skillId]
		if not sc then
			return
		end
		local f = frontier(skillId)
		local cfg = nodes[skillId .. "#" .. rank]
		local cost = (cfg and cfg.price and cfg.price.quantity) or 0
		local sign = (sc.effect.perRank >= 0) and "+" or ""
		tipName.Text = ("%s %s"):format(sc.label or skillId, ROMAN[rank] or tostring(rank))
		tipDesc.Text = ("%s%s %s / rank"):format(sign, tostring(sc.effect.perRank), STAT_LABEL[sc.effect.stat] or sc.effect.stat)
		if rank <= f then
			tipStatus.Text = "W POSIADANIU"
			tipStatus.TextColor3 = Color3.fromRGB(55, 165, 70)
		elseif rank == f + 1 then
			local can = affordable(skillId, skillId .. "#" .. rank)
			tipStatus.Text = ("%s %s%s"):format(CUR_EMOJI[sc.currency] or "", fmt(cost), can and "   ✓ stac cie" or "")
			tipStatus.TextColor3 = can and Color3.fromRGB(55, 165, 70) or Color3.fromRGB(200, 85, 85)
		else
			tipStatus.Text = "ZABLOKOWANE"
			tipStatus.TextColor3 = Color3.fromRGB(120, 125, 140)
		end
		local ap, asz = inst.AbsolutePosition, inst.AbsoluteSize
		tip.Position = UDim2.fromOffset(ap.X + asz.X + 6, ap.Y)
		tip.Visible = true
	end

	-- mapa instancji + pulsujaca obramowka (nakladka OBRYSU hexa = 6 katow) + napisy w hexie + tooltip
	local instById = {}
	local pulseTween = {}
	for _, inst in ipairs(mainFrame:GetDescendants()) do
		local id = inst:GetAttribute("WR_NodeId")
		if id and inst:IsA("GuiButton") then
			instById[id] = inst
			local bg = inst:FindFirstChild("Background")
			local bgIcon = bg and bg:FindFirstChild("Icon")
			-- obramowka 6 katow = WIEKSZY hex tla ZA wezlem (tlo zakrywa srodek, wystaje tylko rabek)
			if bg and bgIcon and not bg:FindFirstChild("WR_Pulse") then
				local ol = Instance.new("ImageLabel")
				ol.Name = "WR_Pulse"; ol.BackgroundTransparency = 1
				ol.AnchorPoint = Vector2.new(0.5, 0.5); ol.Position = UDim2.fromScale(0.5, 0.5)
				ol.Size = UDim2.fromScale(1.16, 1.16)
				ol.Image = FILL; ol.ImageColor3 = COL_PULSE; ol.ImageTransparency = 1
				ol.ZIndex = bgIcon.ZIndex - 1 -- ZA tlem wezla
				ol.Parent = bg
			end
			-- napisy MUSZA miescic sie w hexie: pack daje width=1.5 (wychodzi poza) -> zwezamy + cap
			local ptext = inst:FindFirstChild("PrimaryText")
			if ptext then
				ptext.Size = UDim2.new(0.7, 0, 0.3, 0)
				ptext.TextWrapped = true
				ptext.TextScaled = true
				if not ptext:FindFirstChildOfClass("UITextSizeConstraint") then
					local con = Instance.new("UITextSizeConstraint")
					con.MaxTextSize = 20; con.MinTextSize = 6; con.Parent = ptext
				end
			end
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

	-- pulsowanie obramowki (obrys hexa): on=true -> tween przezroczystosci w petli; false -> stop/ukryj
	local function setPulse(id, on)
		local inst = instById[id]
		local bg = inst and inst:FindFirstChild("Background")
		local ol = bg and bg:FindFirstChild("WR_Pulse")
		if not ol then
			return
		end
		if on then
			if pulseTween[id] then
				return
			end
			ol.ImageTransparency = 0.85
			local tw = TweenService:Create(
				ol,
				TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ ImageTransparency = 0.05 }
			)
			tw:Play()
			pulseTween[id] = tw
		else
			if pulseTween[id] then
				pulseTween[id]:Cancel()
				pulseTween[id] = nil
			end
			ol.ImageTransparency = 1
		end
	end

	-- wyglad + stan jednego wezla wg frontier (owned=niebieski / available=szary+cena+pulse / "?"=szary)
	local function styleNode(inst, id)
		local cfg = nodes[id]
		local bg = inst:FindFirstChild("Background")
		local bgIcon = bg and bg:FindFirstChild("Icon")
		local mainIcon = inst:FindFirstChild("Icon")
		local ptext = inst:FindFirstChild("PrimaryText")
		local price = inst:FindFirstChild("Price")
		local hdr = inst:FindFirstChild("HeaderText")
		local skillId, rank = parseNodeId(id)

		local color, isQ, isOwned, isAvail = COL_UNOWNED, false, false, false
		if not (skillId and rank) then
			color = (id == "root") and COL_ROOT or COL_BRANCH -- root / galaz
		else
			local f = frontier(skillId)
			if rank <= f then
				color = COL_OWNED; isOwned = true
			elseif rank == f + 1 then
				isAvail = true -- odkryta, do kupienia
			else
				isQ = true -- "?"
			end
		end

		if bgIcon then
			bgIcon.Image = FILL
			bgIcon.ImageColor3 = color
		end
		if hdr then
			hdr.Visible = false -- nazwe pokazujemy w PrimaryText (jak og.png)
		end
		if isQ then
			if mainIcon then mainIcon.ImageTransparency = 1 end
			if price then price.Visible = false end
			if ptext then ptext.Text = "?" end
		else
			if mainIcon then mainIcon.ImageTransparency = 0 end
			if price then price.Visible = isAvail end -- cena tylko na odkrytej do kupienia
			if ptext then
				if skillId and rank then
					local sc = SkillConfig.nodes[skillId]
					ptext.Text = ("%s %s"):format((sc and sc.label) or skillId, ROMAN[rank] or tostring(rank))
				else
					ptext.Text = (cfg and cfg.text) or ""
				end
			end
		end
		setPulse(id, isAvail and skillId ~= nil and affordable(skillId, id))
	end

	restyle = function()
		for id, inst in pairs(instById) do
			styleNode(inst, id)
		end
	end

	-- ── progresywne GALEZIE + skille: mapy kolejnosci ──
	local branchOrder = {} -- [idx] = branchId
	local branchSkills = {} -- [branchId] = { [skillIdx] = skillId }
	local skillMeta = {} -- [skillId] = { branch, branchIdx, skillIdx }
	for id, cfg in pairs(nodes) do
		if string.sub(id, 1, 2) == "b:" and cfg.wrBranchIdx then
			branchOrder[cfg.wrBranchIdx] = cfg.wrBranch
		end
		local sId, rk = parseNodeId(id)
		if sId and rk == 1 and cfg.wrSkillIdx then
			branchSkills[cfg.wrBranch] = branchSkills[cfg.wrBranch] or {}
			branchSkills[cfg.wrBranch][cfg.wrSkillIdx] = sId
			skillMeta[sId] = { branch = cfg.wrBranch, branchIdx = cfg.wrBranchIdx, skillIdx = cfg.wrSkillIdx }
		end
	end

	local function branchStarted(branchId) -- czy w galezi ruszyl jakis skill (>=rank1)
		local sk = branchSkills[branchId]
		if not sk then
			return false
		end
		for _, sId in pairs(sk) do
			if frontier(sId) >= 1 then
				return true
			end
		end
		return false
	end
	local function branchUnlocked(branchIdx) -- 1. zawsze; kolejna gdy poprzednia ruszyla
		if not branchIdx or branchIdx <= 1 then
			return true
		end
		local prev = branchOrder[branchIdx - 1]
		return prev ~= nil and branchStarted(prev)
	end
	local function skillUnlocked(skillId) -- 1. w galezi; kolejny gdy poprzedni ruszyl
		local m = skillMeta[skillId]
		if not m then
			return true
		end
		if not branchUnlocked(m.branchIdx) then
			return false
		end
		if m.skillIdx <= 1 then
			return true
		end
		local prev = branchSkills[m.branch] and branchSkills[m.branch][m.skillIdx - 1]
		return prev ~= nil and frontier(prev) >= 1
	end

	-- hook zasiegu: root zawsze; galaz gdy odblokowana; rank gdy skill odblokowany + do frontier+LOOKAHEAD
	NodeTreeClient.wrVisible = function(nodeId)
		if nodeId == "root" then
			return true
		end
		if string.sub(nodeId, 1, 2) == "b:" then
			local cfg = nodes[nodeId]
			return cfg ~= nil and branchUnlocked(cfg.wrBranchIdx)
		end
		local skillId, rank = parseNodeId(nodeId)
		if not (skillId and rank) then
			return true
		end
		if not skillUnlocked(skillId) then
			return false
		end
		return rank <= frontier(skillId) + LOOKAHEAD
	end
	NodeTreeClient.refresh()
	restyle()

	local panning = false
	local lastMouse = Vector2.zero

	NodeTreeClient.treeVisibilityChanged:Connect(function(isVisible)
		header.Visible = isVisible
		closeBtn.Visible = isVisible
		if isVisible then
			-- polprzezroczyste tlo zamiast czarnego void (pack ustawia BackgroundFrame transp=0
			-- -> wygladalo jakby caly ekran zniknal). Ustaw po tweenie otwarcia packa (~0.3s).
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
