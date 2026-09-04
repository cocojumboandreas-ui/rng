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
local GRID_COLUMNS = 3
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

-- jak setTextDeep ale dla TextColor3 — kit renderuje tekst warstwowo (zagniezdzona kopia rysuje sie NA WIERZCHU
-- i przykrywa kolor rodzica), wiec sam kolor na labelu-rodzicu jest niewidoczny bez tego
local function setTextColorDeep(inst, color)
	if not inst then return end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then inst.TextColor3 = color end
	for _, c in ipairs(inst:GetDescendants()) do
		if c:IsA("TextLabel") or c:IsA("TextButton") then c.TextColor3 = color end
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
	local dist = maxExtent * 0.9 + 1.3 -- WR: lekko mniejsze
	-- PRZODEM do kamery: kamera po stronie, w ktora rig PATRZY (LookVector), lekko z boku i z gory
	local hrp = clone:FindFirstChild("HumanoidRootPart", true)
	local baseCF = (hrp and hrp:IsA("BasePart") and hrp.CFrame) or clone:GetPivot()
	local dir = (baseCF.LookVector + baseCF.RightVector * 0.35 + Vector3.new(0, 0.3, 0)).Unit
	cam.CFrame = CFrame.lookAt(bcf.Position + dir * dist, bcf.Position)
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
		-- WR: staty HP/DMG na karcie WYLACZONE (user: pokazuj tylko podglad 3D) — zostaja schowane na stale.
		if stats then stats.Visible = false end
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
	-- Canvas ma UIScale (np. 1.1) -> rozmiary OFFSET renderuja sie *scale; dziel szerokosc absolutna przez
	-- scale, inaczej komorki wychodza za duze i lamia sie do mniej kolumn (+pusty pas z boku) = "rozjechany".
	local _sc = _canvas and _canvas:FindFirstChildOfClass("UIScale")
	local _pad = _gridList:FindFirstChildOfClass("UIPadding")
	local _px = _pad and (_pad.PaddingLeft.Offset + _pad.PaddingRight.Offset) or 0 -- zostaw miejsce na obramowke (stroke rysuje sie poza karta -> clip przy krawedzi okna)
	local cell = math.floor((listW / ((_sc and _sc.Scale) or 1) - _px - (GRID_COLUMNS - 1) * GRID_GAP) / GRID_COLUMNS)
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
	if _gridList then _gridList.CanvasPosition = Vector2.new(0, 0) end -- WR: otwarcie/zmiana zakladki -> scroll na gore
end

-- ── VFX ULEPSZENIA (dopamina): zielone strzalki w gore + pierscien + flash + pop ─────
local _vfxGui
local function vfxLayer()
	if _vfxGui and _vfxGui.Parent then return _vfxGui end
	local g = Instance.new("ScreenGui")
	g.Name = "WR_IndexVFX"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 10000
	g.Parent = LP:WaitForChild("PlayerGui")
	_vfxGui = g
	return g
end
local function popScale(o)
	if not o then return end
	local sc = o:FindFirstChild("WR_PopScale") or Instance.new("UIScale")
	sc.Name = "WR_PopScale"; sc.Parent = o; sc.Scale = 1
	TweenService:Create(sc, TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.22 }):Play()
	task.delay(0.11, function()
		TweenService:Create(sc, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
end
local function playUpgradeVFX(target, showLabel)
	if not target or not target:IsA("GuiObject") or not target:IsDescendantOf(game) then return end
	local Debris = game:GetService("Debris")
	local layer = vfxLayer()
	local ap, asz = target.AbsolutePosition, target.AbsoluteSize
	local cx, cy = ap.X + asz.X / 2, ap.Y + asz.Y / 2
	local GREEN = Color3.fromRGB(76, 138, 62) -- ciemniejszy, wojskowy
	local DARK = Color3.fromRGB(10, 50, 20)
	popScale(target)
	-- jasny flash
	local flash = Instance.new("Frame")
	flash.AnchorPoint = Vector2.new(0.5, 0.5); flash.Position = UDim2.fromOffset(cx, cy)
	flash.Size = UDim2.fromOffset(asz.X * 1.15, asz.Y * 1.15); flash.BackgroundColor3 = GREEN
	flash.BackgroundTransparency = 0.1; flash.BorderSizePixel = 0; flash.Parent = layer
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = flash end
	TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(flash, 0.65)
	-- 2 pierscienie-fale
	for r = 1, 2 do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5); ring.Position = UDim2.fromOffset(cx, cy)
		ring.Size = UDim2.fromOffset(asz.X * 0.5, asz.X * 0.5); ring.BackgroundTransparency = 1; ring.Parent = layer
		do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = ring end
		local st = Instance.new("UIStroke"); st.Color = GREEN; st.Thickness = 9; st.Parent = ring
		local dd = (r - 1) * 0.2
		task.delay(dd, function()
			TweenService:Create(ring, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(asz.X * 3.0, asz.X * 3.0) }):Play()
			TweenService:Create(st, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Transparency = 1, Thickness = 1 }):Play()
		end)
		Debris:AddItem(ring, dd + 0.95)
	end
	-- iskry (zielone kropki na zewnatrz)
	for i = 1, 10 do
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5); dot.Position = UDim2.fromOffset(cx, cy)
		dot.Size = UDim2.fromOffset(9, 9); dot.BackgroundColor3 = GREEN; dot.BorderSizePixel = 0; dot.Parent = layer
		do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = dot end
		local ang = (i / 10) * math.pi * 2
		local distv = 70 + (i % 3) * 30
		TweenService:Create(dot, TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(cx + math.cos(ang) * distv, cy + math.sin(ang) * distv - 34),
			BackgroundTransparency = 1, Size = UDim2.fromOffset(2, 2),
		}):Play()
		Debris:AddItem(dot, 0.95)
	end
	-- DUZE zielone strzalki w gore (glowa-trojkat ▲ + trzon; pewny render)
	for i = 1, 8 do
		local w = 30 + (i % 3) * 12
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1; holder.Size = UDim2.fromOffset(w, w * 2); holder.AnchorPoint = Vector2.new(0.5, 1)
		local jitter = (i - 4.5) / 4.5 * math.max(asz.X * 0.55, 60)
		holder.Position = UDim2.fromOffset(cx + jitter, cy + asz.Y * 0.35); holder.Parent = layer
		local stem = Instance.new("Frame"); stem.AnchorPoint = Vector2.new(0.5, 1); stem.Position = UDim2.fromScale(0.5, 1)
		stem.Size = UDim2.new(0.42, 0, 0.6, 0); stem.BackgroundColor3 = GREEN; stem.BorderSizePixel = 0; stem.Parent = holder
		do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 3); c.Parent = stem end
		local ss = Instance.new("UIStroke"); ss.Color = DARK; ss.Thickness = 2; ss.Parent = stem
		local head = Instance.new("TextLabel"); head.BackgroundTransparency = 1; head.Text = "▲"; head.Font = Enum.Font.GothamBlack
		head.TextColor3 = GREEN; head.TextStrokeColor3 = DARK; head.TextStrokeTransparency = 0; head.TextScaled = true
		head.AnchorPoint = Vector2.new(0.5, 0); head.Position = UDim2.fromScale(0.5, 0); head.Size = UDim2.new(1, 0, 0.5, 0); head.Parent = holder
		local rise = 150 + (i % 4) * 34
		local d = (i - 1) * 0.07
		local info = TweenInfo.new(1.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		task.delay(d, function()
			TweenService:Create(holder, info, { Position = UDim2.fromOffset(cx + jitter, cy - rise) }):Play()
			TweenService:Create(stem, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(ss, info, { Transparency = 1 }):Play()
			TweenService:Create(head, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end)
		Debris:AddItem(holder, d + 1.25)
	end
	-- napis LEVEL UP! — TYLKO na obrazku (showLabel). Mocny: kopia-poswiata + duzy pop + hold + wylot w gore.
	if showLabel then
		local baseY = cy - asz.Y * 0.5
		local glow = Instance.new("TextLabel")
		glow.BackgroundTransparency = 1; glow.Text = "LEVEL UP!"; glow.Font = Enum.Font.FredokaOne
		glow.TextColor3 = GREEN; glow.TextTransparency = 0.35; glow.TextScaled = true
		glow.Size = UDim2.fromOffset(360, 86); glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromOffset(cx, baseY); glow.ZIndex = 1; glow.Parent = layer
		local gs = Instance.new("UIScale"); gs.Scale = 0.2; gs.Parent = glow
		local lu = Instance.new("TextLabel")
		lu.BackgroundTransparency = 1; lu.Text = "LEVEL UP!"; lu.Font = Enum.Font.FredokaOne
		lu.TextColor3 = Color3.fromRGB(255, 240, 120); lu.TextStrokeColor3 = DARK; lu.TextStrokeTransparency = 0
		lu.TextScaled = true; lu.Size = UDim2.fromOffset(340, 80); lu.AnchorPoint = Vector2.new(0.5, 0.5)
		lu.Position = UDim2.fromOffset(cx, baseY); lu.ZIndex = 2; lu.Parent = layer
		local st = Instance.new("UIStroke"); st.Color = DARK; st.Thickness = 4; st.Parent = lu
		local ls = Instance.new("UIScale"); ls.Scale = 0.2; ls.Parent = lu
		local popInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(ls, popInfo, { Scale = 1.28 }):Play()
		TweenService:Create(gs, popInfo, { Scale = 1.45 }):Play()
		task.delay(0.35, function()
			TweenService:Create(ls, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.1 }):Play()
		end)
		task.delay(0.9, function()
			local outInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			TweenService:Create(lu, outInfo, { Position = UDim2.fromOffset(cx, baseY - 95), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			TweenService:Create(glow, outInfo, { Position = UDim2.fromOffset(cx, baseY - 95), TextTransparency = 1 }):Play()
		end)
		Debris:AddItem(lu, 1.75); Debris:AddItem(glow, 1.75)
	end
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

function IndexController._selectUnit(unitId, skipViewport)
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
	if _pw.rarity then setTextColorDeep(_pw.rarity, TIER_COLOR[tier.revealTier] or TIER_COLOR[1]) end
	setText(_pw.levelInfo, "Level " .. (level + 1)) -- display-only +1: stored level 0-based, shown as 1-based

	-- 3D ikona w detalu
	if _pw.iconHolder and not skipViewport then
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
	if _bottom.infoText then
		setTextDeep(_bottom.infoText, ("Index luck bonus: <font color='rgb(100,230,120)'>+%.1fx</font>"):format(_luckBonus))
	end
	local nt = nextThreshold()
	local pct = _overall.percent or 0
	if nt then
		local frac = math.clamp(pct / nt.pct, 0, 1)
		if _bottom.progressFill then
			_bottom.progressFill.Size = UDim2.new(frac, 0, _bottom.progressFill.Size.Y.Scale, _bottom.progressFill.Size.Y.Offset)
		end
		if _bottom.claimBtn then
			if nt.reached then
				setTextDeep(_bottom.claimLbl or _bottom.claimBtn, ("CLAIM +%.1f"):format(nt.luck))
				_bottom.claimBtn.BackgroundColor3 = Color3.fromRGB(80, 170, 90)
				_bottom.claimBtn.AutoButtonColor = true
				_bottom.claimBtn.Active = true
			else
				setTextDeep(_bottom.claimLbl or _bottom.claimBtn, ("To %d%%"):format(nt.pct))
				_bottom.claimBtn.BackgroundColor3 = Color3.fromRGB(60, 62, 74)
				_bottom.claimBtn.AutoButtonColor = false
				_bottom.claimBtn.Active = false
			end
		end
	else
		if _bottom.progressFill then
			_bottom.progressFill.Size = UDim2.new(1, 0, _bottom.progressFill.Size.Y.Scale, _bottom.progressFill.Size.Y.Offset)
		end
		if _bottom.claimBtn then
			setTextDeep(_bottom.claimLbl or _bottom.claimBtn, "All claimed")
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
		_gridList.ClipsDescendants = true -- WR: przycinaj przewijanie do okna (bylo false -> tresc wychodzila poza)
		-- pelna szerokosc + zero bocznych marginesow (grafik: List width 0.988 + UIPadding.Left=10)
		_gridList.Size = UDim2.new(1, 0, _gridList.Size.Y.Scale, _gridList.Size.Y.Offset)
		_gridList.Position = UDim2.new(0.5, 0, _gridList.Position.Y.Scale, _gridList.Position.Y.Offset)
		local lpad = _gridList:FindFirstChildOfClass("UIPadding")
		if lpad then lpad.PaddingLeft = UDim.new(0, 5); lpad.PaddingRight = UDim.new(0, 5); lpad.PaddingTop = UDim.new(0, 5); lpad.PaddingBottom = UDim.new(0, 5) end
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
				playUpgradeVFX(_pw.iconHolder, true) -- efekt + napis LEVEL UP TYLKO na obrazku (guzik bez efektu)
				IndexController._selectUnit(unitId, true) -- tylko staty/level, BEZ przebudowy viewportu (zero migania)
				-- BEZ renderGrid(): karty pokazuja sam podglad (staty schowane) -> level-up ich nie zmienia, nie odswiezamy siatki
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
	-- WR: napis CLAIM wychodzil poza przycisk (label od 50% szerokosci, szerszy niz przycisk). Wysrodkuj+zmiesc wszystkie warstwy "Coins".
	if _bottom.claimBtn then
		local _cll = _bottom.claimBtn:FindFirstChildOfClass("UIListLayout")
		if _cll then _cll:Destroy() end -- WR: UIListLayout wypychal napis poza przycisk -> usun, pozycjonuj recznie
		for _, lbl in ipairs(_bottom.claimBtn:GetDescendants()) do
			if lbl:IsA("TextLabel") and lbl.Name == "Coins" then
				lbl.AnchorPoint = Vector2.new(0.5, 0.5)
				lbl.Position = UDim2.fromScale(0.5, 0.5)
				lbl.Size = UDim2.new(1, -16, 0.7, 0)
				lbl.TextScaled = true
				lbl.TextXAlignment = Enum.TextXAlignment.Center
				-- WR: kit ma 2 warstwy (ciemna zewnetrzna + biala zagniezdzona z przesunieciem) = brzydki "cien".
				-- Zostaw jedna czysto biala warstwe, ukryj ciemna kopie (zrodlo cienia).
				if lbl:FindFirstChild("Coins") then
					lbl.TextTransparency = 1 -- ciemna warstwa-cien -> niewidoczna
					local us = lbl:FindFirstChildOfClass("UIStroke")
					if us then us.Transparency = 1 end
				else
					lbl.TextColor3 = Color3.fromRGB(255, 255, 255) -- biala warstwa -> czysty bialy
				end
			end
		end
	end
		_bottom.multiplier = resolve(bi, "Frame", "Frame", "Multiplier")
		_bottom.infoText = resolve(bi, "Frame", "Frame", "Text")
		_bottom.progressFill = resolve(bi, "Frame", "ProgressBar", "Progress")
		if _bottom.multiplier then _bottom.multiplier.Visible = false end -- zlaczone w jedna linie (infoText, RichText)
		if _bottom.infoText then
			_bottom.infoText.RichText = true
			for _, d in ipairs(_bottom.infoText:GetDescendants()) do
				if d:IsA("TextLabel") then d.RichText = true end
			end
		end
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
