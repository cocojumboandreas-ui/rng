--!nonstrict
-- StarterPlayerScripts/Controllers/UnitTooltipController.luau  (KLIENT)
-- KARTA INFO (ikona 3D + DMG/s + HP) + biala OTOCZKA gdy najedziesz na WLASNA jednostke na planszy.
-- TYLKO w TRYBIE WOLNYM (nie w edycji budowania — tam BuildController ma wlasny hover + statystyki na karcie
-- panelu — ani podczas fali). Pozycja karty: statyczny BLOK -> na SRODKU jednostki; reszta (bron/soldier/
-- pulapka) -> NAD glowa (nie skacze, nie zaslania). Otoczka = Highlight (bialy kontur, jak Start Wave).
-- Wartosci na razie z configu (HP = hp, DMG/s = combat.dmg * combat.fireRate) — placeholder; docelowy system
-- wartosci ogarniemy przy indexie (UI ziomka).
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

-- ikona 3D jednostki (ViewportFrame), cache per unitId
local function icon(unitId)
	if _iconCache[unitId] then return _iconCache[unitId]:Clone() end
	local vpf = Instance.new("ViewportFrame")
	vpf.BackgroundTransparency = 1
	local tmpl = UnitModelFactory.get(unitId)
	if tmpl then
		local cam = Instance.new("Camera"); vpf.CurrentCamera = cam; cam.Parent = vpf
		local m = tmpl:Clone(); m.Parent = vpf
		local cf, size = m:GetBoundingBox()
		local dist = math.max(size.X, size.Y, size.Z) * 1.7
		cam.CFrame = CFrame.new(cf.Position + Vector3.new(dist * 0.6, size.Y * 0.35, dist), cf.Position)
	end
	_iconCache[unitId] = vpf
	return vpf:Clone()
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_UnitTooltip"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 250000; gui.Enabled = false; gui.Parent = LP:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Card"; frame.Size = UDim2.fromOffset(184, 216); frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.BackgroundColor3 = Color3.fromRGB(58, 62, 74); frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0; frame.Parent = gui
	-- mniejsza karta (nie zaslania calej jednostki) — UIScale skaluje ramke + calą zawartosc
	local uscale = Instance.new("UIScale"); uscale.Scale = 0.55; uscale.Parent = frame
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 10); fc.Parent = frame
	local fs = Instance.new("UIStroke"); fs.Color = Color3.fromRGB(20, 22, 28); fs.Thickness = 2; fs.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8); pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8); pad.Parent = frame
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical; list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 6); list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"; title.LayoutOrder = 1; title.Size = UDim2.new(1, 0, 0, 20)
	title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBold; title.TextSize = 15
	title.TextColor3 = Color3.new(1, 1, 1); title.Text = ""; title.TextScaled = false
	title.TextTruncate = Enum.TextTruncate.AtEnd; title.Parent = frame
	local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(20, 22, 28); ts.Thickness = 2; ts.Parent = title

	-- pudelko z ikona
	local box = Instance.new("Frame")
	box.Name = "IconBox"; box.LayoutOrder = 2; box.Size = UDim2.fromOffset(120, 120)
	box.BackgroundColor3 = Color3.fromRGB(44, 47, 56); box.BorderSizePixel = 0; box.Parent = frame
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = box
	local bs = Instance.new("UIStroke"); bs.Color = Color3.fromRGB(200, 60, 60); bs.Thickness = 2; bs.Parent = box

	-- wiersz statystyk
	local stats = Instance.new("Frame")
	stats.Name = "Stats"; stats.LayoutOrder = 3; stats.Size = UDim2.new(1, 0, 0, 34)
	stats.BackgroundTransparency = 1; stats.Parent = frame
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Horizontal; sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sl.VerticalAlignment = Enum.VerticalAlignment.Center; sl.Padding = UDim.new(0, 6); sl.Parent = stats

	local function pill(order, prefixIcon, color)
		local p = Instance.new("Frame")
		p.LayoutOrder = order; p.Size = UDim2.fromOffset(82, 30); p.BackgroundColor3 = Color3.fromRGB(44, 47, 56)
		p.BorderSizePixel = 0; p.Parent = stats
		local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 7); pc.Parent = p
		local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(20, 22, 28); ps.Thickness = 1.5; ps.Parent = p
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 13; lbl.TextColor3 = color; lbl.Text = prefixIcon .. " 0"; lbl.Parent = p
		local ls = Instance.new("UIStroke"); ls.Color = Color3.fromRGB(20, 22, 28); ls.Thickness = 1.5; ls.Parent = lbl
		return lbl
	end
	_dmgLbl = pill(1, "⚔️", Color3.fromRGB(255, 255, 255))
	_hpLbl = pill(2, "❤️", Color3.fromRGB(255, 120, 120))

	_gui, _frame, _title, _iconHolder = gui, frame, title, box
end

-- pokaz karte dla unitId; (sx,sy) = punkt zaczepienia (juz z GuiInset), anchor = kotwica frame. Klamruje na ekran.
local function showAt(unitId, sx, sy, anchor)
	local st = statsOf(unitId)
	if not st then UnitTooltip.hide(); return end
	if _curUnit ~= unitId then
		_curUnit = unitId
		_title.Text = st.name
		for _, ch in ipairs(_iconHolder:GetChildren()) do
			if ch:IsA("ViewportFrame") then ch:Destroy() end
		end
		local ic = icon(unitId)
		ic.Size = UDim2.fromScale(1, 1); ic.Position = UDim2.fromScale(0, 0); ic.Parent = _iconHolder
		_dmgLbl.Text = "⚔️ " .. fmt(st.dps) .. "/s"
		_hpLbl.Text = "❤️ " .. fmt(st.hp)
	end
	anchor = anchor or Vector2.new(0.5, 1)
	_frame.AnchorPoint = anchor
	-- realny rozmiar (juz po UIScale); fallback gdy pierwsza klatka nie przeliczyla
	local w = _frame.AbsoluteSize.X; if w < 1 then w = 184 * 0.55 end
	local h = _frame.AbsoluteSize.Y; if h < 1 then h = 216 * 0.55 end
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

-- biala otoczka (Highlight) na jednostce pod kursorem — jak podswietlenie Start Wave, lekkie przyciemnienie fill
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
	hl.FillTransparency = 0.6
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
	local function inBuildMode()
		if not BuildController then
			local c = script.Parent:FindFirstChild("BuildController")
			if c then BuildController = require(c) end
		end
		return BuildController and BuildController.IsBuildMode and BuildController.IsBuildMode() or false
	end

	RunService.RenderStepped:Connect(function()
		if _waveActive or inBuildMode() then -- karta swiata TYLKO w TRYBIE WOLNYM
			hideAll()
			return
		end
		local m = unitUnderCursor()
		local cam = Workspace.CurrentCamera
		if m and cam then
			setOutline(m)
			-- Tylko statyczny BLOK -> karta na SRODKU (aa1). Reszta (bron/soldier/pulapka) -> karta NAD glowa:
			-- soldiery to animowane rigi — wysrodkowana karta skakalaby (bbox pelza z animacja), wiec dajemy NAD.
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
				-- dalej -> GetBoundingBox (srodek/wierzch) ODLATUJE w eter. Bierzemy PIVOT (X/Z = srodek kratki)
				-- + wierzch tylko CZESCI CIALA (party blisko pivota), zeby karta stala nad glowa.
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
