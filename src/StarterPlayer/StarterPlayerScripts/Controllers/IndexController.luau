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

-- koszt WYSWIETLANY (mirror LevelService.GetCost)
local function costOf(unitId, level)
	local u = GameConfig.Units[unitId]
	local base = math.floor(((u and u.rarityN) or 1) * GameConfig.Level.baseCostK)
	return math.floor(base * (GameConfig.Level.costGrowth ^ level))
end

local TIER_COLOR = {
	[1] = Color3.fromRGB(150, 150, 160), [2] = Color3.fromRGB(90, 190, 110),
	[3] = Color3.fromRGB(80, 140, 230), [4] = Color3.fromRGB(170, 90, 220),
	[5] = Color3.fromRGB(240, 180, 60),
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
	local nameLbl = slot:FindFirstChild("Text")
	local stats = slot:FindFirstChild("Stats")
	local atkFrame = stats and stats:FindFirstChild("Attack")
	local hpFrame = stats and stats:FindFirstChild("Health")

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
		local mult = GameConfig.Level.growthPerLevel ^ (_levels[unitId] or 0)
		if u.combat then
			setText(atkFrame, "⚔ " .. fmtNum(math.floor(u.combat.dmg * mult + 0.5)))
			setText(hpFrame, "❤ " .. fmtNum(u.hp or 0))
		else
			setText(atkFrame, "⚔ -")
			setText(hpFrame, "❤ " .. fmtNum(math.floor((u.hp or 0) * mult + 0.5)))
		end
		if stats then stats.Visible = true end
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
		slot.BackgroundTransparency = math.min(1, (_gridTemplate.BackgroundTransparency or 0) + 0.35)
	end
	slot.Parent = _gridList
	return slot
end

local function renderGrid()
	clearGrid()
	local cat = _catsById[_activeVariant]
	local discovered = (cat and cat.discovered) or {}
	for i, unitId in ipairs(_unitOrder) do
		buildSlot(unitId, discovered[unitId] == true, i)
	end
end

-- ── panel detali (PetWindow) ──────────────────────────────────────────────────────
local function refreshLevelUpBtn(unitId)
	local level = _levels[unitId] or 0
	if not _pw.levelUp then return end
	if level >= GameConfig.Level.maxLevel then
		setText(_pw.levelUp, "Poziom MAX")
		_pw.levelUp.BackgroundColor3 = Color3.fromRGB(70, 74, 86)
	else
		local cost = costOf(unitId, level)
		setText(_pw.levelUp, "Ulepsz — " .. fmtNum(cost))
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
	local mult = GameConfig.Level.growthPerLevel ^ level
	local multNext = GameConfig.Level.growthPerLevel ^ (level + 1)

	setText(_pw.name, u.displayName or unitId)
	setText(_pw.rarity, ("%s · 1 in %d"):format(tier.name, u.rarityN))
	if _pw.rarity then _pw.rarity.TextColor3 = TIER_COLOR[tier.revealTier] or Color3.new(1, 1, 1) end
	setText(_pw.levelInfo, "Poziom " .. level)

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
		local curDmg = math.floor(u.combat.dmg * mult + 0.5)
		local nextDmg = math.floor(u.combat.dmg * multNext + 0.5)
		setText(_pw.atk, fmtNum(curDmg))
		setText(_pw.hp, fmtNum(u.hp or 0))
		setText(_pw.change1, ("⚔ %s → %s"):format(fmtNum(curDmg), fmtNum(nextDmg)))
		setText(_pw.change2, ("Szybkostrzelnosc %s/s"):format(tostring(u.combat.fireRate or "-")))
	else
		local curHp = math.floor((u.hp or 0) * mult + 0.5)
		local nextHp = math.floor((u.hp or 0) * multNext + 0.5)
		setText(_pw.atk, "-")
		setText(_pw.hp, fmtNum(curHp))
		setText(_pw.change1, ("❤ %s → %s"):format(fmtNum(curHp), fmtNum(nextHp)))
		setText(_pw.change2, u.def and ("Pancerz " .. u.def) or "")
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
				setText(_bottom.claimLbl or _bottom.claimBtn, ("ODBIERZ +%.1f"):format(nt.luck))
				_bottom.claimBtn.BackgroundColor3 = Color3.fromRGB(80, 170, 90)
				_bottom.claimBtn.AutoButtonColor = true
				_bottom.claimBtn.Active = true
			else
				setText(_bottom.claimLbl or _bottom.claimBtn, ("Do %d%%"):format(nt.pct))
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
			setText(_bottom.claimLbl or _bottom.claimBtn, "Wszystko odebrane")
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
		_unitOrder[#_unitOrder + 1] = id
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
	if _gridTemplate then
		_gridTemplate.Visible = false -- oryginal to szablon; klonujemy z niego
		pcall(function() _gridList.AutomaticCanvasSize = Enum.AutomaticSize.Y end)
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
				setText(_pw.levelUp, (reason == "NotEnoughCoins") and "Brak monet!" or (reason == "MaxLevel" and "Poziom MAX" or "Blad"))
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

	-- live: nowy wpis per-wariant + %/luck
	Net.get("IndexUpdated").OnClientEvent:Connect(function(p)
		if not p then return end
		if p.variant and p.unitId and _catsById[p.variant] then
			local cat = _catsById[p.variant]
			if not cat.discovered[p.unitId] then
				cat.discovered[p.unitId] = true
				cat.count = (cat.count or 0) + 1
				_overall.count = (_overall.count or 0) + 1
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
