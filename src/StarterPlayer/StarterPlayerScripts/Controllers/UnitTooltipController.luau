--!nonstrict
-- StarterPlayerScripts/Controllers/UnitTooltipController.luau  (KLIENT)
-- KARTA INFO (ikona 3D + DMG/s + HP) + biala OTOCZKA gdy najedziesz na WLASNA jednostke na planszy.
-- TYLKO w TRYBIE WOLNYM (nie w edycji budowania - tam BuildController ma wlasny hover). Pozycja karty:
-- statyczny BLOK -> na SRODKU jednostki; reszta (bron/soldier/pulapka) -> NAD glowa. Otoczka = Highlight.
-- Wartosci z configu (HP = hp, DMG/s = combat.dmg * combat.fireRate). Karta wyskalowana czytelnie (#tooltip-fix).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitModelFactory = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UnitModelFactory"))

local UnitTooltip = {}
local LP = Players.LocalPlayer
local WHITE = Color3.fromRGB(255, 255, 255) -- kontur jak przy najechaniu na Start Wave

local _gui, _frame, _title, _iconHolder, _dmgLbl, _hpLbl = nil, nil, nil, nil, nil, nil
local _nameLabels = {} -- wszystkie labelki nazwy do ustawienia (template ma warstwowa PetName: outer+inner)
local _dmgPrefix, _hpPrefix = "DMG", "HP" -- prefiks przed liczba; z template bierzemy emoji, z fallbacku ASCII
local _rarityFrame = nil -- badge rzadkosci z template — chowany (placed units nie maja rarity)
local _iconCache = {}
local _curUnit = nil -- aktualnie pokazywany unitId (zeby nie przebudowywac co klatke)
local _hovered = nil -- Model z aktywna otoczka WR_TipHL
local _waveActive = false -- fala trwa -> chowamy karte i otoczke

-- 2.9K / 10.0K / 1.2M
local function fmt(n)
	n = n or 0
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n + 0.5))
end

-- statystyki z configu (placeholder): DMG/s = dmg*fireRate, HP = hp
local function statsOf(unitId)
	local u = GameConfig.Units[unitId]
	if not u then return nil end
	local dps = u.combat and (u.combat.dmg or 0) * (u.combat.fireRate or 1) or 0
	return { name = u.displayName or unitId, dps = dps, hp = u.hp or 0 }
end

-- ikona 3D jednostki (ViewportFrame), cache per unitId. OSWIETLENIE jawne (ViewportFrame nie bierze swiatla
-- swiata) + kadr 3/4 z przodu, zeby postac byla widoczna i wypelniala pudelko.
local function icon(unitId)
	if _iconCache[unitId] then return _iconCache[unitId]:Clone() end
	local vpf = Instance.new("ViewportFrame")
	-- JASNE tlo + max ambient: ciemne jednostki (np. Heavy Trooper) zlewaly sie z ciemna karta -> nieczytelne.
	-- Jasne tlo daje kontrast (jak ikona), pelny ambient rozswietla model. Zaokraglenie pod styl karty.
	vpf.BackgroundColor3 = Color3.fromRGB(205, 210, 220)
	vpf.BackgroundTransparency = 0
	vpf.Ambient = Color3.fromRGB(255, 255, 255)
	vpf.LightColor = Color3.fromRGB(255, 255, 255)
	vpf.LightDirection = Vector3.new(-0.3, -1, -0.4)
	local vc = Instance.new("UICorner"); vc.CornerRadius = UDim.new(0, 8); vc.Parent = vpf
	local tmpl = UnitModelFactory.get(unitId)
	if tmpl then
		local cam = Instance.new("Camera"); cam.FieldOfView = 38; vpf.CurrentCamera = cam; cam.Parent = vpf
		local m = tmpl:Clone(); m.Parent = vpf
		local cf, size = m:GetBoundingBox()
		local maxd = math.max(size.X, size.Y, size.Z, 1)
		local dist = maxd * 1.45 -- blizej = wieksza jednostka w boxie (user: powiekszyc)
		-- kadr 3/4-przod: kamera lekko z boku i z gory, patrzy w srodek modelu
		cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist * 0.5, size.Y * 0.22, dist), cf.Position)
	end
	_iconCache[unitId] = vpf
	return vpf:Clone()
end

-- podepnij referencje do labelek z KARTY ZIOMKA (ReplicatedStorage.WR_UnitCardTemplate = PetWindow):
-- PetName (warstwowa outer+inner), Health/Attack TextLabel, PetIcon (tu wchodzi 3D viewport), Rarity (chowany).
local function wireTemplateCard(card)
	local content = card:FindFirstChild("Content", true)
	local petName = content and content:FindFirstChild("PetName")
	_nameLabels = {}
	if petName then
		if petName:IsA("TextLabel") then _nameLabels[#_nameLabels + 1] = petName end
		local inner = petName:FindFirstChild("PetName")
		if inner and inner:IsA("TextLabel") then _nameLabels[#_nameLabels + 1] = inner end
	end
	_title = _nameLabels[1]
	local info = content and content:FindFirstChild("Info")
	_iconHolder = info and info:FindFirstChild("PetIcon")
	if _iconHolder and _iconHolder:IsA("ImageLabel") then _iconHolder.Image = ""; _iconHolder.ImageTransparency = 1 end -- placeholder off -> 3D viewport
	_rarityFrame = info and info:FindFirstChild("Rarity")
	if _rarityFrame then _rarityFrame.Visible = false end -- placed units nie maja rarity -> chowamy badge
	local stats = content and content:FindFirstChild("Stats")
	_hpLbl = stats and stats:FindFirstChild("Health") and stats.Health:FindFirstChild("TextLabel")
	_dmgLbl = stats and stats:FindFirstChild("Attack") and stats.Attack:FindFirstChild("TextLabel")
	-- prefiks (emoji z template) wyciagniety z tekstu -> zero emoji w kodzie; nadpisujemy tylko liczbe
	_hpPrefix = (_hpLbl and _hpLbl.Text:match("^(%S+)")) or "HP"
	_dmgPrefix = (_dmgLbl and _dmgLbl.Text:match("^(%S+)")) or "DMG"
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_UnitTooltip"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 250000; gui.Enabled = false; gui.Parent = LP:WaitForChild("PlayerGui")

	-- KARTA ZIOMKA (PetWindow) jesli jest w ReplicatedStorage -> klon; inaczej fallback (kodowa karta nizej).
	local tmpl = ReplicatedStorage:FindFirstChild("WR_UnitCardTemplate")
	if tmpl then
		local card = tmpl:Clone()
		card.Name = "Card"
		card.Size = UDim2.fromOffset(212, 240)
		card.AnchorPoint = Vector2.new(0.5, 1)
		card.Visible = true
		card.Parent = gui
		wireTemplateCard(card)
		_gui, _frame = gui, card
		return
	end

	local frame = Instance.new("Frame")
	frame.Name = "Card"; frame.Size = UDim2.fromOffset(212, 252); frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.BackgroundColor3 = Color3.fromRGB(48, 52, 64); frame.BackgroundTransparency = 0.03
	frame.BorderSizePixel = 0; frame.Parent = gui
	-- UIScale = pelny rozmiar (dawne 0.55 robilo karte NIECZYTELNA); zostaje pod ew. tuning per-rozdzielczosc.
	local uscale = Instance.new("UIScale"); uscale.Scale = 1.0; uscale.Parent = frame
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 12); fc.Parent = frame
	local fs = Instance.new("UIStroke"); fs.Color = Color3.fromRGB(16, 18, 24); fs.Thickness = 2.5; fs.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10); pad.Parent = frame
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical; list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 8); list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"; title.LayoutOrder = 1; title.Size = UDim2.new(1, 0, 0, 26)
	title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBold; title.TextSize = 21
	title.TextColor3 = Color3.new(1, 1, 1); title.Text = ""; title.TextScaled = false
	title.TextTruncate = Enum.TextTruncate.AtEnd; title.Parent = frame
	local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(16, 18, 24); ts.Thickness = 2.5; ts.Parent = title

	-- pudelko z ikona 3D
	local box = Instance.new("Frame")
	box.Name = "IconBox"; box.LayoutOrder = 2; box.Size = UDim2.fromOffset(150, 150)
	box.BackgroundColor3 = Color3.fromRGB(38, 41, 51); box.BorderSizePixel = 0; box.Parent = frame
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 10); bc.Parent = box
	local bs = Instance.new("UIStroke"); bs.Color = Color3.fromRGB(210, 66, 66); bs.Thickness = 2.5; bs.Parent = box

	-- wiersz statystyk
	local stats = Instance.new("Frame")
	stats.Name = "Stats"; stats.LayoutOrder = 3; stats.Size = UDim2.new(1, 0, 0, 40)
	stats.BackgroundTransparency = 1; stats.Parent = frame
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Horizontal; sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sl.VerticalAlignment = Enum.VerticalAlignment.Center; sl.Padding = UDim.new(0, 8); sl.Parent = stats

	local function pill(order, prefixIcon, color)
		local p = Instance.new("Frame")
		p.LayoutOrder = order; p.Size = UDim2.fromOffset(94, 38); p.BackgroundColor3 = Color3.fromRGB(38, 41, 51)
		p.BorderSizePixel = 0; p.Parent = stats
		local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 9); pc.Parent = p
		local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(16, 18, 24); ps.Thickness = 1.5; ps.Parent = p
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 18; lbl.TextColor3 = color; lbl.Text = prefixIcon .. " 0"; lbl.Parent = p
		local ls = Instance.new("UIStroke"); ls.Color = Color3.fromRGB(16, 18, 24); ls.Thickness = 1.6; ls.Parent = lbl
		return lbl
	end
	_dmgLbl = pill(1, "DMG", Color3.fromRGB(255, 235, 140))
	_hpLbl = pill(2, "HP", Color3.fromRGB(150, 255, 150))

	_gui, _frame, _title, _iconHolder = gui, frame, title, box
	_nameLabels = { title } -- fallback: jedna labelka nazwy; prefiksy zostaja "DMG"/"HP"
end

-- pokaz karte dla unitId; (sx,sy) = punkt zaczepienia (juz z GuiInset), anchor = kotwica frame. Klamruje na ekran.
local function showAt(unitId, sx, sy, anchor)
	local st = statsOf(unitId)
	if not st then UnitTooltip.hide(); return end
	if _curUnit ~= unitId then
		_curUnit = unitId
		for _, lbl in ipairs(_nameLabels) do lbl.Text = st.name end -- template: outer+inner; fallback: title
		if _iconHolder then
			for _, ch in ipairs(_iconHolder:GetChildren()) do
				if ch:IsA("ViewportFrame") then ch:Destroy() end
			end
			local ic = icon(unitId)
			ic.Size = UDim2.fromScale(1, 1); ic.Position = UDim2.fromScale(0, 0); ic.Parent = _iconHolder
		end
		if _dmgLbl then _dmgLbl.Text = _dmgPrefix .. " " .. fmt(st.dps) .. "/s" end
		if _hpLbl then _hpLbl.Text = _hpPrefix .. " " .. fmt(st.hp) end
	end
	anchor = anchor or Vector2.new(0.5, 1)
	_frame.AnchorPoint = anchor
	-- realny rozmiar (juz po UIScale); fallback gdy pierwsza klatka nie przeliczyla
	local w = _frame.AbsoluteSize.X; if w < 1 then w = 212 end
	local h = _frame.AbsoluteSize.Y; if h < 1 then h = 252 end
	local vp = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
	local left = math.clamp(sx - anchor.X * w, 4, math.max(4, vp.X - w - 4))
	local top = math.clamp(sy - anchor.Y * h, 4, math.max(4, vp.Y - h - 4))
	_frame.Position = UDim2.fromOffset(left + anchor.X * w, top + anchor.Y * h)
	_gui.Enabled = true
end

function UnitTooltip.hide()
	if _gui then _gui.Enabled = false end
	_curUnit = nil
end

-- biala otoczka (Highlight) na jednostce pod kursorem - jak podswietlenie Start Wave, lekkie przyciemnienie fill
local function clearOutline()
	if _hovered and _hovered.Parent then
		local h = _hovered:FindFirstChild("WR_TipHL")
		if h then h:Destroy() end
	end
	_hovered = nil
end

local function setOutline(m)
	if m == _hovered then return end
	clearOutline()
	local hl = Instance.new("Highlight")
	hl.Name = "WR_TipHL"
	hl.Adornee = m
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.OutlineColor = WHITE
	hl.OutlineTransparency = 0
	hl.FillColor = Color3.new(0, 0, 0)
	hl.FillTransparency = 1 -- user: bez ciemnej nakladki na jednostce (0.6 przyciemnialo ja mocno); sam bialy obrys
	hl.Parent = m
	_hovered = m
end

local function hideAll()
	clearOutline()
	UnitTooltip.hide()
end

-- raycast do WLASNEJ postawionej jednostki pod kursorem -> Model albo nil (idziemy w gore do atrybutu PlacementId)
local function unitUnderCursor()
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local units = Workspace:FindFirstChild("WR_Units")
	if not units then return nil end
	local mp = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mp.X, mp.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { units }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 800, params)
	if not hit then return nil end
	local m = hit.Instance
	while m and m:GetAttribute("PlacementId") == nil do m = m.Parent end
	if m and m:GetAttribute("OwnerUserId") == LP.UserId then return m end
	return nil
end

function UnitTooltip.start()
	build()

	-- stan fali (jak WeaponCameraGate): WaveProgress -> trwa; WaveEnded/RunSummary -> koniec
	Net.get("WaveProgress").OnClientEvent:Connect(function()
		_waveActive = true
	end)
	Net.get("WaveEnded").OnClientEvent:Connect(function()
		_waveActive = false
	end)
	Net.get("RunSummary").OnClientEvent:Connect(function()
		_waveActive = false
	end)

	-- lazy ref do BuildController (tryb budowania ma wlasny hover -> tam nie pokazujemy naszej karty)
	local BuildController
	-- lazy ref do NodeTreeClient (drzewo umiejetnosci) -> w trybie umiejetnosci NIE pokazujemy karty/otoczki
	local NodeTreeClient
	local function treeOpen()
		if not NodeTreeClient then
			local nt = ReplicatedStorage:FindFirstChild("NodeTree")
			local mod = nt and nt:FindFirstChild("NodeTreeClient")
			if mod then NodeTreeClient = require(mod) end
		end
		return NodeTreeClient and NodeTreeClient.isTreeVisible and NodeTreeClient.isTreeVisible() or false
	end
	local function inBuildMode()
		if not BuildController then
			local c = script.Parent:FindFirstChild("BuildController")
			if c then BuildController = require(c) end
		end
		return BuildController and BuildController.IsBuildMode and BuildController.IsBuildMode() or false
	end
	-- panel na SRODKU ekranu (Sklep/Indeks/Koniec rundy/Offline/Ustawienia) otwarty -> input pochloniety przez UI:
	-- NIE pokazujemy karty/otoczki swiata (raycast omija GUI, wiec sprawdzamy jawnie). Dziala dla myszy i dotyku.
	local PANELS = { "Store", "Index", "RoundOver", "OfflineEarn", "Settings" }
	local function panelOpen()
		local pg = LP.PlayerGui
		for _, name in ipairs(PANELS) do
			local g = pg:FindFirstChild(name)
			local c = g and g:FindFirstChild("Canvas")
			if c and c.Visible then
				return true
			end
		end
		return false
	end

	RunService.RenderStepped:Connect(function()
		if _waveActive or inBuildMode() or treeOpen() or panelOpen() then -- karta TYLKO w trybie wolnym
			hideAll()
			return
		end
		local m = unitUnderCursor()
		local cam = Workspace.CurrentCamera
		if m and cam then
			setOutline(m)
			-- Tylko statyczny BLOK -> karta na SRODKU. Reszta (bron/soldier/pulapka) -> karta NAD glowa:
			-- soldiery to rigi - wysrodkowana karta skakalaby (bbox pelza), wiec dajemy NAD.
			local cf, size = m:GetBoundingBox()
			local inset = GuiService:GetGuiInset()
			local uid = m:GetAttribute("UnitId")
			local u = GameConfig.Units[uid]
			local isBlock = u ~= nil and u.combat == nil and u.category ~= "trap"
			if isBlock then
				-- karta wysrodkowana NA bloku (statyczna bryla)
				local spC = cam:WorldToViewportPoint(cf.Position)
				showAt(uid, spC.X + inset.X, spC.Y + inset.Y, Vector2.new(0.5, 0.5))
			else
				-- karta NAD jednostka. UWAGA: rigi maja efekty (WR_Tracer/WR_Muzzle) zaparkowane ~139 studow
				-- dalej -> GetBoundingBox ODLATUJE. Bierzemy PIVOT (X/Z = srodek kratki) + wierzch CZESCI CIALA.
				local piv = m:GetPivot().Position
				local topY = piv.Y
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") and (d.Position - piv).Magnitude < 30 then
						local t = d.Position.Y + d.Size.Y * 0.5
						if t > topY then topY = t end
					end
				end
				local sp = cam:WorldToViewportPoint(Vector3.new(piv.X, topY + 0.5, piv.Z))
				showAt(uid, sp.X + inset.X, sp.Y + inset.Y - 6, Vector2.new(0.5, 1))
			end
		else
			hideAll()
		end
	end)
end

return UnitTooltip
