--!nonstrict
-- StarterPlayerScripts/Controllers/IndexController.luau  (KLIENT)
-- Steruje DESIGNEROWYM UI kolekcji (StarterGui.Index, place-owned) — NIE tworzymy wlasnego panelu.
-- Mapowanie na elementy grafika:
--   * zakladki Buttons.Normal/Golden/Rainbow -> kategorie regular/shiny/galaxy (pozycyjnie; Wrogowie=stub, pominiete)
--   * siatka ContentStroke.Content.List: klon Template per typ jednostki; odkryty -> ViewportFrame 3D (model z
--     Assets.Units) + nazwa + mini-staty; nieodkryty -> "?" (zaciemniony)
--   * PetWindow (detal): PetName, Info.Rarity + 3D ikona, Stats.Health/Attack, Level.LevelInfo + LevelUp (Ulepsz),
--     UpgradedStats.Change (podglad nastepnego poziomu)
--   * BottomInfo: ProgressBar = % do najblizszego NIEODEBRANEGO progu, Multiplier = aktualny bonus luck,
--     LevelUp = "ODBIERZ +X" gdy prog osiagniety (cyklicznie 25->50->100; ClaimIndexLuck)
-- Kontrakt serwera bez zmian: GetIndexState (RF), IndexUpdated (S->C), LevelUpUnit (RF), ClaimIndexLuck (RF).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)
local HudOverlay = require(script.Parent:WaitForChild("HudOverlay"))

local IndexController = {}
local LP = Players.LocalPlayer
local ASSETS_UNITS = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Units")

-- zakladka grafika (kolejnosc) -> kategoria unitowa (variant)
local TAB_TO_CAT = { "regular", "shiny", "galaxy" } -- Normal, Golden, Rainbow
local TAB_ORDER = { "Normal", "Golden", "Rainbow" }

-- siatka: ile kart w rzedzie. Rozmiar karty liczony w PX z szerokosci List tak, ze
-- GRID_COLUMNS kart + (GRID_COLUMNS-1) odstepow = pelna szerokosc (zero bocznych marginesow).
local GRID_COLUMNS = 4
local GRID_GAP = 13 -- = UIListLayout.Padding.Offset grafika

-- ── stan ────────────────────────────────────────────────────────────────────────
local _catsById = {} -- id -> {id,label,kind,variant,discovered={uid=true},count,total,percent}
local _overall = { count = 0, total = 0, percent = 0 }
local _luckBonus = 0
local _levels = {} -- uid -> poziom
local _thresholds = {} -- [{pct,luck,reached,claimed}]
local _coins = 0
local _activeVariant = "regular"
local _unitOrder = {} -- uid po rarityN rosnaco
local _selUnit = nil -- aktualnie wybrany w PetWindow

-- ── G: CELEBRACJA NOWEGO ODKRYCIA (banner + sparkle) — standalone ScreenGui, dziala tez gdy panel zamkniety ──
local VARIANT_ACCENT = {
	regular = Color3.fromRGB(255, 235, 150), -- delikatne zloto
	shiny = Color3.fromRGB(255, 205, 60), -- zloto
	galaxy = Color3.fromRGB(200, 130, 255), -- fiolet
}
local VARIANT_TAG = { regular = "NEW DISCOVERY", shiny = "NEW GOLDEN", galaxy = "NEW RAINBOW" }
local _discoGui = nil

local function sparkleBurst(parent, accent)
	for i = 1, 12 do
		local s = Instance.new("Frame")
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Position = UDim2.fromScale(0.5, 0.5)
		s.Size = UDim2.fromOffset(10, 10)
		s.BackgroundColor3 = accent
		s.BorderSizePixel = 0
		s.Rotation = 45
		s.ZIndex = 13
		local uc = Instance.new("UICorner")
		uc.CornerRadius = UDim.new(0.3, 0)
		uc.Parent = s
		s.Parent = parent
		local ang = (i / 12) * math.pi * 2
		local dist = math.random(90, 150)
		local tw = TweenService:Create(
			s,
			TweenInfo.new(0.6 + math.random() * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.new(0.5, math.cos(ang) * dist, 0.5, math.sin(ang) * dist),
				Rotation = s.Rotation + math.random(-120, 120),
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(2, 2),
			}
		)
		tw:Play()
		tw.Completed:Once(function() s:Destroy() end)
	end
end

local function celebrateDiscovery(unitId, variant)
	local accent = VARIANT_ACCENT[variant] or VARIANT_ACCENT.regular
	local tag = VARIANT_TAG[variant] or "NEW DISCOVERY"
	local uname = (GameConfig.Units[unitId] and GameConfig.Units[unitId].displayName) or unitId
	if not _discoGui then
		local gui = Instance.new("ScreenGui")
		gui.Name = "WR_IndexDisco"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 400
		gui.Parent = LP:WaitForChild("PlayerGui")
		_discoGui = gui
	end
	local old = _discoGui:FindFirstChild("Banner")
	if old then old:Destroy() end
	local holder = Instance.new("Frame")
	holder.Name = "Banner"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.2)
	holder.Size = UDim2.fromOffset(360, 92)
	holder.BackgroundTransparency = 1
	holder.Parent = _discoGui
	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = Color3.fromRGB(28, 26, 40)
	pill.BackgroundTransparency = 0.1
	pill.BorderSizePixel = 0
	pill.ZIndex = 11
	pill.Parent = holder
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 16)
	pc.Parent = pill
	local ps = Instance.new("UIStroke")
	ps.Color = accent
	ps.Thickness = 2.5
	ps.Parent = pill
	local tagL = Instance.new("TextLabel")
	tagL.BackgroundTransparency = 1
	tagL.AnchorPoint = Vector2.new(0.5, 0.5)
	tagL.Position = UDim2.fromScale(0.5, 0.3)
	tagL.Size = UDim2.fromScale(0.94, 0.4)
	tagL.Font = Enum.Font.GothamBlack
	tagL.TextScaled = true
	tagL.Text = "✨ " .. tag .. "! ✨"
	tagL.TextColor3 = accent
	tagL.ZIndex = 12
	tagL.Parent = holder
	local ts = Instance.new("UIStroke")
	ts.Color = Color3.new(0, 0, 0)
	ts.Thickness = 2
	ts.Parent = tagL
	local nameL = Instance.new("TextLabel")
	nameL.BackgroundTransparency = 1
	nameL.AnchorPoint = Vector2.new(0.5, 0.5)
	nameL.Position = UDim2.fromScale(0.5, 0.7)
	nameL.Size = UDim2.fromScale(0.94, 0.36)
	nameL.Font = Enum.Font.GothamBold
	nameL.TextScaled = true
	nameL.Text = uname
	nameL.TextColor3 = Color3.new(1, 1, 1)
	nameL.ZIndex = 12
	nameL.Parent = holder
	local ns = Instance.new("UIStroke")
	ns.Color = Color3.new(0, 0, 0)
	ns.Thickness = 2
	ns.Parent = nameL
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = holder
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	sparkleBurst(holder, accent)
	-- auto-hide: TEN banner znika po ~1.9s. Self-contained (destroy TYLKO wlasny holder) — bez token-race,
	-- ktory przy szybkich/kolejnych odkryciach potrafil skasowac swiezy banner. Nowe odkrycie w miedzyczasie
	-- i tak czysci poprzedni przez old:Destroy() na starcie funkcji.
	local myHolder = holder
	local myPill = pill
	task.delay(1.9, function()
		if not myHolder.Parent then return end
		for _, d in ipairs(myHolder:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(myPill, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		task.delay(0.4, function()
			if myHolder then myHolder:Destroy() end
		end)
	end)
end

-- ── elementy UI (resolve raz w start) ─────────────────────────────────────────────
local _gui, _canvas, _tabs, _gridList, _gridTemplate, _petWindow
local _pw = {} -- PetWindow lisce: name, rarity, iconHolder, hp, atk, levelInfo, levelUp, change1, change2
local _bottom = {} -- BottomInfo lisce: claimBtn, claimLbl, multiplier, progressFill, infoText

-- ── helpery ──────────────────────────────────────────────────────────────────────
local function fmtNum(n)
	n = n or 0
	if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n + 0.5))
end

local function resolve(root, ...)
	local cur = root
	for _, seg in ipairs({ ... }) do
		if not cur then return nil end
		cur = cur:FindFirstChild(seg)
	end
	return cur
end

-- ustaw tekst na labelu I zagniezdzonych labelach (kit renderuje tekst warstwowo dla obrysu)
local function setText(inst, txt)
	if not inst then return end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then inst.Text = txt end
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("TextLabel") or c:IsA("TextButton") then c.Text = txt end
	end
end

-- jak setText ale GLEBOKO (wszystkie potomki) — guzik-moneta ma kwote w zagniezdzonym Coins.Coins
local function setTextDeep(inst, txt)
	if not inst then return end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then inst.Text = txt end
	for _, c in ipairs(inst:GetDescendants()) do
		if c:IsA("TextLabel") or c:IsA("TextButton") then c.Text = txt end
	end
end

-- koszt WYSWIETLANY (mirror LevelService.GetCost)
local function costOf(unitId, level)
	local u = GameConfig.Units[unitId]
	local base = math.floor(((u and u.rarityN) or 1) * GameConfig.Level.baseCostK)
	return math.floor(base * (GameConfig.Level.costGrowth ^ level))
end

local TIER_COLOR = {
	[1] = Color3.fromRGB(150, 150, 160), [2] = Color3.fromRGB(90, 190, 110),
	[3] = Color3.fromRGB(80, 140, 230), [4] = Color3.fromRGB(170, 90, 220),
	[5] = Color3.fromRGB(240, 180, 60), [6] = Color3.fromRGB(230, 60, 70),
}
local function tierFor(rarityN)
	for _, t in ipairs(GameConfig.Rarity.tiers) do
		if rarityN <= t.maxN then return t end
	end
	return GameConfig.Rarity.tiers[#GameConfig.Rarity.tiers]
end

-- ── ViewportFrame 3D miniatura modelu jednostki ───────────────────────────────────
local function makeUnitViewport(modelName)
	local src = modelName and ASSETS_UNITS:FindFirstChild(modelName)
	if not src then return nil end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "WR_Viewport"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.5)
	vp.Ambient = Color3.fromRGB(200, 200, 200)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-1, -1, -1)
	vp.ZIndex = 2
	local clone = src:Clone()
	clone.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 55
	cam.Parent = vp
	vp.CurrentCamera = cam
	local bcf, bsize = clone:GetBoundingBox()
	local maxExtent = math.max(bsize.X, bsize.Y, bsize.Z)
	local dist = maxExtent * 1.5 + 3
	local offset = Vector3.new(1, 0.55, 1).Unit * dist
	cam.CFrame = CFrame.lookAt(bcf.Position + offset, bcf.Position)
	return vp
end

-- ── siatka slotow ────────────────────────────────────────────────────────────────
local function clearGrid()
	for _, ch in ipairs(_gridList:GetChildren()) do
		if ch:GetAttribute("WR_Slot") then ch:Destroy() end
	end
end

local function buildSlot(unitId, discovered, order)
	local u = GameConfig.Units[unitId]
	local slot = _gridTemplate:Clone()
	slot:SetAttribute("WR_Slot", true)
	slot.Name = "Slot_" .. unitId
	slot.LayoutOrder = order
	slot.Visible = true

	local tier = tierFor(u.rarityN)
	local border = TIER_COLOR[tier.revealTier] or TIER_COLOR[1]
	local stroke = slot:FindFirstChildWhichIsA("UIStroke")
	if stroke then stroke.Color = border end

	local petIcon = slot:FindFirstChild("PetIcon")
	local textLbls = {}
	for _, c in ipairs(slot:GetChildren()) do
		if c:IsA("TextLabel") and c.Name == "Text" then textLbls[#textLbls + 1] = c end
	end
	local nameLbl = textLbls[1]
	local oddsLbl = textLbls[2] -- druga "Text" grafika (placeholder "256x") -> szanse "1 in N"
	local stats = slot:FindFirstChild("Stats")
	local atkFrame = stats and stats:FindFirstChild("Attack")
	local hpFrame = stats and stats:FindFirstChild("Health")
	if oddsLbl then oddsLbl.Visible = false end -- referencja: karta bez liczby (placeholder "256x" schowany)

	if discovered then
		slot.BackgroundTransparency = _gridTemplate.BackgroundTransparency
		-- 3D miniatura zamiast placeholder ikony (jak brak modelu -> zostaw placeholder)
		if petIcon then
			local vp = makeUnitViewport(u.model)
			if vp then
				petIcon.ImageTransparency = 1 -- schowaj placeholder, pokaz viewport
				vp.Parent = slot
			end
		end
		setText(nameLbl, u.displayName or unitId)
		if nameLbl then nameLbl.Visible = true end
		local lvl = _levels[unitId] or 0
		local dmgMult = GameConfig.Level.growthPerLevel ^ lvl
		local hpGrowth = u.combat and (GameConfig.Level.attackHpGrowthPerLevel or GameConfig.Level.growthPerLevel) or GameConfig.Level.growthPerLevel
		local hpMult = hpGrowth ^ lvl
		if u.combat then
			local dps = u.combat.dmg * dmgMult * (u.combat.fireRate or 1)
			setText(atkFrame, "⚔ " .. fmtNum(dps) .. "/s")
			setText(hpFrame, "❤ " .. fmtNum(math.floor((u.hp or 0) * hpMult + 0.5)))
		else
			if atkFrame then atkFrame.Visible = false end -- blok: bez dmg, sam HP
			setText(hpFrame, "❤ " .. fmtNum(math.floor((u.hp or 0) * hpMult + 0.5)))
		end
		-- staty HP/DMG tylko na hover (domyslnie schowane -> karta pokazuje sam model 3D)
		if stats then stats.Visible = false end
		slot.MouseEnter:Connect(function() if stats then stats.Visible = true end end)
		slot.MouseLeave:Connect(function() if stats then stats.Visible = false end end)
		local btn = slot:IsA("GuiButton") and slot or slot:FindFirstChildWhichIsA("GuiButton")
		if btn then
			btn.Active = true
			btn.MouseButton1Click:Connect(function() IndexController._selectUnit(unitId) end)
		end
	else
		-- nieodkryty: "?" zaciemniony
		if petIcon then petIcon.ImageTransparency = 1 end
		setText(nameLbl, "?")
		if stats then stats.Visible = false end
		slot.BackgroundTransparency = math.min(0.4, (_gridTemplate.BackgroundTransparency or 0) + 0.10)
	end
	slot.Parent = _gridList
	return slot
end

-- rozmiar karty w px: (szerokosc widoczna List - odstepy) / kolumny -> 4 karty wypelniaja rzad bez luk
local function applyCellSizes()
	if not _gridList then return end
	local listW = _gridList.AbsoluteWindowSize.X
	if listW <= 0 then listW = _gridList.AbsoluteSize.X end
	if listW <= 0 then return end
	local cell = math.floor((listW - (GRID_COLUMNS - 1) * GRID_GAP) / GRID_COLUMNS)
	if cell <= 0 then return end
	for _, ch in ipairs(_gridList:GetChildren()) do
		if ch:GetAttribute("WR_Slot") then
			ch.Size = UDim2.fromOffset(cell, cell)
		end
	end
end

local function renderGrid()
	clearGrid()
	local cat = _catsById[_activeVariant]
	local discovered = (cat and cat.discovered) or {}
	for i, unitId in ipairs(_unitOrder) do
		buildSlot(unitId, discovered[unitId] == true, i)
	end
	applyCellSizes()
end

-- ── panel detali (PetWindow) ──────────────────────────────────────────────────────
local function refreshLevelUpBtn(unitId)
	local level = _levels[unitId] or 0
	if not _pw.levelUp then return end
	if level >= GameConfig.Level.maxLevel then
		setTextDeep(_pw.levelUp, "MAX")
		_pw.levelUp.BackgroundColor3 = Color3.fromRGB(70, 74, 86)
	else
		local cost = costOf(unitId, level)
		setTextDeep(_pw.levelUp, fmtNum(cost)) -- kwota na guziku-monecie (gleboko: Coins.Coins)
		_pw.levelUp.BackgroundColor3 = (_coins >= cost) and Color3.fromRGB(80, 165, 95) or Color3.fromRGB(150, 70, 70)
	end
end

function IndexController._selectUnit(unitId)
	local u = GameConfig.Units[unitId]
	if not u then return end
	_selUnit = unitId
	if _petWindow then _petWindow.Visible = true end
	local tier = tierFor(u.rarityN)
	local level = _levels[unitId] or 0
	local dmgMult = GameConfig.Level.growthPerLevel ^ level
	local dmgMultNext = GameConfig.Level.growthPerLevel ^ (level + 1)
	local hpGrowth = u.combat and (GameConfig.Level.attackHpGrowthPerLevel or GameConfig.Level.growthPerLevel) or GameConfig.Level.growthPerLevel
	local hpMult = hpGrowth ^ level
	local hpMultNext = hpGrowth ^ (level + 1)

	setText(_pw.name, u.displayName or unitId)
	setText(_pw.rarity, tier.name) -- tier jednostki (Common/Rare/Super Rare/Mystic/Legend/Mysterious), nie wariant zakladki
	if _pw.rarity then _pw.rarity.TextColor3 = TIER_COLOR[tier.revealTier] or TIER_COLOR[1] end
	setText(_pw.levelInfo, "Level " .. (level + 1)) -- display-only +1: stored level 0-based, shown as 1-based

	-- 3D ikona w detalu
	if _pw.iconHolder then
		local old = _pw.iconHolder:FindFirstChild("WR_Viewport")
		if old then old:Destroy() end
		local vp = makeUnitViewport(u.model)
		if vp then
			_pw.iconHolder.ImageTransparency = 1
			vp.Parent = _pw.iconHolder
		else
			_pw.iconHolder.ImageTransparency = 0
		end
	end

	if u.combat then
		local curDps = math.floor(u.combat.dmg * dmgMult * (u.combat.fireRate or 1) + 0.5)
		local nextDps = math.floor(u.combat.dmg * dmgMultNext * (u.combat.fireRate or 1) + 0.5)
		local curHp = math.floor((u.hp or 0) * hpMult + 0.5)
		local nextHp = math.floor((u.hp or 0) * hpMultNext + 0.5)
		if _pw.atk then _pw.atk.Visible = true end
		setText(_pw.atk, "⚔ " .. fmtNum(curDps) .. "/s")
		setText(_pw.hp, "❤ " .. fmtNum(curHp))
		setText(_pw.change1, ("❤ +%s"):format(fmtNum(nextHp - curHp)))
		setText(_pw.change2, ("⚔ +%s/s"):format(fmtNum(nextDps - curDps)))
	else
		local curHp = math.floor((u.hp or 0) * hpMult + 0.5)
		local nextHp = math.floor((u.hp or 0) * hpMultNext + 0.5)
		if _pw.atk then _pw.atk.Visible = false end -- blok nie ma dmg -> pokazujemy sam HP
		setText(_pw.hp, "❤ " .. fmtNum(curHp))
		setText(_pw.change1, ("❤ +%s"):format(fmtNum(nextHp - curHp)))
		setText(_pw.change2, u.def and ("Armor " .. u.def) or "")
	end
	refreshLevelUpBtn(unitId)
end

-- ── dolny pasek: progres do najblizszego nieodebranego progu + ODBIERZ ─────────────
-- zwraca prog {pct,luck,reached,claimed} lub nil gdy wszystko odebrane
local function nextThreshold()
	for _, t in ipairs(_thresholds) do
		if not t.claimed then return t end
	end
	return nil
end

local function refreshBottom()
	setText(_bottom.multiplier, ("+%.1f"):format(_luckBonus))
	local nt = nextThreshold()
	local pct = _overall.percent or 0
	if nt then
		local frac = math.clamp(pct / nt.pct, 0, 1)
		if _bottom.progressFill then
			_bottom.progressFill.Size = UDim2.new(frac, 0, _bottom.progressFill.Size.Y.Scale, _bottom.progressFill.Size.Y.Offset)
		end
		setText(_bottom.infoText, ("%d%% / %d%%"):format(math.floor(pct + 0.5), nt.pct))
		if _bottom.claimBtn then
			if nt.reached then
				setText(_bottom.claimLbl or _bottom.claimBtn, ("CLAIM +%.1f"):format(nt.luck))
				_bottom.claimBtn.BackgroundColor3 = Color3.fromRGB(80, 170, 90)
				_bottom.claimBtn.AutoButtonColor = true
				_bottom.claimBtn.Active = true
			else
				setText(_bottom.claimLbl or _bottom.claimBtn, ("To %d%%"):format(nt.pct))
				_bottom.claimBtn.BackgroundColor3 = Color3.fromRGB(60, 62, 74)
				_bottom.claimBtn.AutoButtonColor = false
				_bottom.claimBtn.Active = false
			end
		end
	else
		if _bottom.progressFill then
			_bottom.progressFill.Size = UDim2.new(1, 0, _bottom.progressFill.Size.Y.Scale, _bottom.progressFill.Size.Y.Offset)
		end
		setText(_bottom.infoText, "100%")
		if _bottom.claimBtn then
			setText(_bottom.claimLbl or _bottom.claimBtn, "All claimed")
			_bottom.claimBtn.BackgroundColor3 = Color3.fromRGB(55, 85, 60)
			_bottom.claimBtn.AutoButtonColor = false
			_bottom.claimBtn.Active = false
		end
	end
end

-- ── stan z serwera ────────────────────────────────────────────────────────────────
local function applyState(state)
	_catsById = {}
	for _, c in ipairs(state.categories or {}) do
		c.discovered = c.discovered or {}
		if c.variant then _catsById[c.variant] = c end
	end
	_overall = state.overall or _overall
	_luckBonus = state.luckBonus or 0
	_levels = state.levels or {}
	_thresholds = state.thresholds or {}
	renderGrid()
	refreshBottom()
	if _selUnit then IndexController._selectUnit(_selUnit) end
end

local function setActiveVariant(variant)
	_activeVariant = variant
	-- podswietl aktywna zakladke
	for i, name in ipairs(TAB_ORDER) do
		local tab = _tabs and _tabs:FindFirstChild(name)
		if tab then
			local on = (TAB_TO_CAT[i] == variant)
			local st = tab:FindFirstChildWhichIsA("UIStroke")
			if st then st.Enabled = on end
			tab.BackgroundTransparency = on and 0 or 0.4
		end
	end
	renderGrid()
end

-- ── otwarcie / zamkniecie ─────────────────────────────────────────────────────────
local function closePanel()
	if _canvas then _canvas.Visible = false end
	HudOverlay.exit()
end

local function openPanel()
	if not _canvas then return end
	HudOverlay.enter(true) -- zostaw monety (koszt Ulepsz)
	_canvas.Visible = true
	if _petWindow then _petWindow.Visible = false end
	_selUnit = nil
	local ok, state = pcall(function()
		return Net.get("GetIndexState"):InvokeServer()
	end)
	if ok and state then applyState(state) end
end

-- ── budowa (resolve elementow grafika) ────────────────────────────────────────────
function IndexController.start()
	-- kolejnosc jednostek: rarityN rosnaco
	_unitOrder = {}
	for id in pairs(GameConfig.Units) do
		-- test_* = zaslepki deweloperskie (nadal w puli Roll, celowo NIE ruszane) — wykluczone TYLKO z Indeksu
		if string.sub(id, 1, 5) ~= "test_" then
			_unitOrder[#_unitOrder + 1] = id
		end
	end
	table.sort(_unitOrder, function(a, b)
		return GameConfig.Units[a].rarityN < GameConfig.Units[b].rarityN
	end)

	local pg = LP:WaitForChild("PlayerGui")
	_gui = pg:WaitForChild("Index", 15)
	if not _gui then
		warn("[IndexController] brak PlayerGui.Index — UI indeksu grafika nie znaleziony")
		return
	end
	_gui.ResetOnSpawn = false
	_canvas = _gui:WaitForChild("Canvas", 5)
	if not _canvas then
		warn("[IndexController] Index bez Canvas — nie podepne indeksu")
		return
	end
	_canvas.Visible = false

	-- X
	local x = _canvas:FindFirstChild("X")
	if x and x:IsA("GuiButton") then x.MouseButton1Click:Connect(closePanel) end

	-- zakladki
	_tabs = _canvas:FindFirstChild("Buttons")
	if _tabs then
		for i, name in ipairs(TAB_ORDER) do
			local tab = _tabs:FindFirstChild(name)
			if tab and tab:IsA("GuiButton") then
				local variant = TAB_TO_CAT[i]
				tab.MouseButton1Click:Connect(function() setActiveVariant(variant) end)
			end
		end
	end

	-- siatka
	_gridList = resolve(_canvas, "ContentStroke", "Content", "List")
	_gridTemplate = _gridList and _gridList:FindFirstChild("Template")
	if _gridList then
		-- grafik zostawil 2 szablony "Template"; chowamy WSZYSTKIE (inaczej drugi renderuje sie jak smieciowa karta)
		for _, c in ipairs(_gridList:GetChildren()) do
			if c.Name == "Template" then c.Visible = false end
		end
		pcall(function() _gridList.AutomaticCanvasSize = Enum.AutomaticSize.Y end)
		-- pelna szerokosc + zero bocznych marginesow (grafik: List width 0.988 + UIPadding.Left=10)
		_gridList.Size = UDim2.new(1, 0, _gridList.Size.Y.Scale, _gridList.Size.Y.Offset)
		_gridList.Position = UDim2.new(0.5, 0, _gridList.Position.Y.Scale, _gridList.Position.Y.Offset)
		local lpad = _gridList:FindFirstChildOfClass("UIPadding")
		if lpad then lpad.PaddingLeft = UDim.new(0, 0); lpad.PaddingRight = UDim.new(0, 0) end
		-- rozmiar kart zalezy od szerokosci List -> przelicz gdy sie zmieni (otwarcie panelu / zmiana rozdzielczosci)
		_gridList:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyCellSizes)
	end

	-- PetWindow (detal)
	_petWindow = _canvas:FindFirstChild("PetWindow")
	local pl = resolve(_petWindow, "Content", "List")
	if pl then
		_pw.name = pl:FindFirstChild("PetName")
		_pw.rarity = resolve(pl, "Info", "Rarity")
		_pw.iconHolder = resolve(pl, "Info", "PetIcon")
		_pw.hp = resolve(pl, "Stats", "Health")
		_pw.atk = resolve(pl, "Stats", "Attack")
		_pw.levelInfo = resolve(pl, "Level", "LevelInfo")
		_pw.levelUp = resolve(pl, "Level", "LevelUp")
		local ups = pl:FindFirstChild("UpgradedStats")
		if ups then
			local changes = {}
			for _, ch in ipairs(ups:GetChildren()) do
				if ch.Name == "Change" and ch:IsA("TextLabel") then changes[#changes + 1] = ch end
			end
			_pw.change1, _pw.change2 = changes[1], changes[2]
		end
	end
	if _pw.levelUp and _pw.levelUp:IsA("GuiButton") then
		_pw.levelUp.MouseButton1Click:Connect(function()
			local unitId = _selUnit
			if not unitId then return end
			local res = Net.get("LevelUpUnit"):InvokeServer(unitId)
			if type(res) == "table" and res.ok then
				_levels[unitId] = res.newLevel
				IndexController._selectUnit(unitId)
				renderGrid() -- staty na slocie tez sie zmienily
			else
				local reason = type(res) == "table" and res.reason or "?"
				setTextDeep(_pw.levelUp, (reason == "NotEnoughCoins") and "Not enough!" or (reason == "MaxLevel" and "MAX" or "Error"))
				task.delay(0.9, function()
					if _selUnit == unitId then refreshLevelUpBtn(unitId) end
				end)
			end
		end)
	end

	-- BottomInfo (pasek progresu + ODBIERZ)
	local bi = _canvas:FindFirstChild("BottomInfo")
	if bi then
		_bottom.claimBtn = bi:FindFirstChild("LevelUp")
		_bottom.claimLbl = _bottom.claimBtn and _bottom.claimBtn:FindFirstChild("Coins")
		_bottom.multiplier = resolve(bi, "Frame", "Frame", "Multiplier")
		_bottom.infoText = resolve(bi, "Frame", "Frame", "Text")
		_bottom.progressFill = resolve(bi, "Frame", "ProgressBar", "Progress")
	end
	if _bottom.claimBtn and _bottom.claimBtn:IsA("GuiButton") then
		_bottom.claimBtn.MouseButton1Click:Connect(function()
			local nt = nextThreshold()
			if not nt or not nt.reached then return end
			local res = Net.get("ClaimIndexLuck"):InvokeServer(nt.pct)
			if type(res) == "table" and res.ok then
				_luckBonus = res.luckBonus or _luckBonus
				for _, t in ipairs(_thresholds) do
					if t.pct == nt.pct then t.claimed = true end
				end
				refreshBottom()
			end
		end)
	end

	-- domyslna zakladka
	setActiveVariant("regular")

	-- saldo monet (kolor Ulepsz)
	Net.get("CoinsSync").OnClientEvent:Connect(function(p)
		if type(p) == "table" and type(p.balance) == "number" then
			_coins = p.balance
			if _selUnit then refreshLevelUpBtn(_selUnit) end
		end
	end)

	-- G: prebuduj _catsById.discovered na starcie (niezaleznie od otwarcia panelu) -> celebracje odkryc
	-- dzialaja OD RAZU (gracz odkrywa jednostki rollujac z ZAMKNIETYM Indeksem). openPanel i tak rebuilduje.
	task.spawn(function()
		if next(_catsById) ~= nil then return end
		local ok, state = pcall(function() return Net.get("GetIndexState"):InvokeServer() end)
		if ok and state and next(_catsById) == nil then
			for _, c in ipairs(state.categories or {}) do
				c.discovered = c.discovered or {}
				if c.variant then _catsById[c.variant] = c end
			end
		end
	end)

	-- live: nowy wpis per-wariant + %/luck
	Net.get("IndexUpdated").OnClientEvent:Connect(function(p)
		if not p then return end
		if p.variant and p.unitId and _catsById[p.variant] then
			local cat = _catsById[p.variant]
			if not cat.discovered[p.unitId] then
				cat.discovered[p.unitId] = true
				cat.count = (cat.count or 0) + 1
				_overall.count = (_overall.count or 0) + 1
				celebrateDiscovery(p.unitId, p.variant) -- G: banner + sparkle na pierwszym odkryciu
			end
		end
		_overall.percent = p.percent or _overall.percent
		_luckBonus = p.luckBonus or _luckBonus
		-- prog moze sie odblokowac (reached) — przelicz reached lokalnie
		for _, t in ipairs(_thresholds) do
			t.reached = (_overall.percent or 0) >= t.pct
		end
		if _canvas and _canvas.Visible then
			refreshBottom()
			if p.variant == _activeVariant then renderGrid() end
		end
	end)

	IndexController.Open = openPanel -- HUD ziomka (SideButtons.Index) wola to
	IndexController.Close = closePanel
end

return IndexController
