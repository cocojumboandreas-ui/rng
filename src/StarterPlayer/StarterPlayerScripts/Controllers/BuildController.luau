--!nonstrict
-- StarterPlayerScripts/Controllers/BuildController.luau  (KLIENT — tryb budowania, wzor: Power Roll)
-- ZBUDUJ -> tryb budowania: panel po lewej (Bloki/Bron, siatka posiadanych z inventory + miniatury 3D),
-- wybor przedmiotu -> GHOST na kratce pod kursorem (zielony/czerwony = mozna/nie mozna) + KOLO ZASIEGU
-- dla broni. Klik/POSTAW = PlaceUnit. Usun = tryb kasowania (klik jednostki -> RemoveUnit). Licznik X/budzet.
-- Jednostki auto-obracaja sie w strone wroga (faceDir z GetPlotInfo) — brak recznego obrotu w v1.
-- Serwer autorytatywny: klient wysyla tylko intencje; walidacja i tak po stronie serwera.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GridMath = require(Framework:WaitForChild("GridMath"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitModelFactory = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UnitModelFactory"))

local BuildController = {}

local LP = Players.LocalPlayer
local GREEN = Color3.fromRGB(80, 220, 100)
local RED = Color3.fromRGB(220, 70, 70)

-- ── stan ──
local _on = false
local _mode = "place" -- place | delete
local _counts = {} -- invKey -> count (inventory)
local _plot = nil -- {plotId, gridOrigin(CFrame), width, depth, cellSize, faceDir}
local _budget = GameConfig.Grid.baseCellBudget
local _sel = nil -- { key, unitId, fp, isWeapon, range }
local _ghost, _ring = nil, nil
local _cell = nil -- {x,z} aktualna kratka pod kursorem
local _thumbCache = {}

-- UI refs
local _panel, _grid, _counter, _tabBtns, _postawBtn, _delBtn, _hint = nil, nil, nil, nil, nil, nil, nil
local _activeTab = "weapon"

-- ── geometria kratek ──
local function cellKey(x, z) return x .. "," .. z end

-- zajetosc wlasnego plotu z atrybutow modeli WR_Units + suma zajetych kratek
local function occupancy()
	local occ, used = {}, 0
	local units = Workspace:FindFirstChild("WR_Units")
	if units then
		for _, m in ipairs(units:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("OwnerUserId") == LP.UserId then
				local x, z = m:GetAttribute("CellX"), m:GetAttribute("CellZ")
				local w, d = m:GetAttribute("FpW") or 1, m:GetAttribute("FpD") or 1
				if x and z then
					for _, c in ipairs(GridMath.footprintCells(x, z, { w = w, d = d })) do
						occ[cellKey(c.x, c.z)] = true
					end
					used += w * d
				end
			end
		end
	end
	return occ, used
end

-- punkt na plaszczyznie siatki pod kursorem -> kratka (x,z), clamp do siatki
local function cursorCell()
	if not _plot then return nil end
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local mp = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mp.X, mp.Y)
	local originY = _plot.gridOrigin.Position.Y
	if math.abs(ray.Direction.Y) < 1e-4 then return nil end
	local t = (originY - ray.Origin.Y) / ray.Direction.Y
	if t < 0 then return nil end
	local hit = ray.Origin + ray.Direction * t
	local go = _plot.gridOrigin.Position
	local cs = _plot.cellSize
	local x = math.floor((hit.X - go.X) / cs) + 1
	local z = math.floor((hit.Z - go.Z) / cs) + 1
	if x < 1 or x > _plot.width or z < 1 or z > _plot.depth then return nil end
	return { x = x, z = z }
end

local function validAt(x, z)
	if not _sel then return false end
	local fp = _sel.fp
	local occ, used = occupancy()
	for _, c in ipairs(GridMath.footprintCells(x, z, fp)) do
		if c.x < 1 or c.x > _plot.width or c.z < 1 or c.z > _plot.depth then return false end
		if occ[cellKey(c.x, c.z)] then return false end
	end
	if used + fp.w * fp.d > _budget then return false end
	return true
end

-- ── ghost + kolo zasiegu ──
local function tint(model, color, transparency)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Color = color; d.Transparency = transparency; d.Material = Enum.Material.ForceField
		end
	end
end

local function makeGhost()
	if _ghost then _ghost:Destroy(); _ghost = nil end
	if _ring then _ring:Destroy(); _ring = nil end
	if not _sel then return end
	local tmpl = UnitModelFactory.get(_sel.unitId)
	if not tmpl then return end
	local g = tmpl:Clone()
	if not g.PrimaryPart then
		g.PrimaryPart = g:FindFirstChild("HumanoidRootPart") or g:FindFirstChildWhichIsA("BasePart")
	end
	-- fit do footprintu (jak renderer, uproszczone)
	local cs = _plot.cellSize
	local cellW, cellD = _sel.fp.w * cs, _sel.fp.d * cs
	local sz = g:GetExtentsSize()
	local f = math.min(cellW / math.max(sz.X, 0.01), cellD / math.max(sz.Z, 0.01)) * 0.85
	if g.ScaleTo and f < 1 then g:ScaleTo(f) end
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false end
	end
	g.Parent = Workspace
	_ghost = g
	-- podglad = WIDOCZNY realny model + Highlight walidacji (zielony/czerwony), zamiast przezroczystego ghosta
	local hl = Instance.new("Highlight")
	hl.Adornee = g
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = GREEN
	hl.FillTransparency = 0.7
	hl.OutlineColor = GREEN
	hl.OutlineTransparency = 0
	hl.Parent = g
	if _sel.isWeapon and _sel.range then
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.4, _sel.range * 2, _sel.range * 2)
		ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CastShadow = false
		ring.Material = Enum.Material.Neon; ring.Color = GREEN; ring.Transparency = 0.72
		ring.Parent = Workspace
		_ring = ring
	end
end

local function updateGhost()
	if not _ghost or not _plot then return end
	local c = cursorCell()
	_cell = c
	if not c then
		_ghost.Parent = nil
		if _ring then _ring.Parent = nil end
		if _postawBtn then _postawBtn.Visible = false end
		return
	end
	_ghost.Parent = Workspace
	local center = GridMath.cellToWorld(_plot.gridOrigin, _plot.cellSize, c.x, c.z, _sel.fp).Position
	local groundY = _plot.gridOrigin.Position.Y
	_ghost:PivotTo(CFrame.lookAlong(Vector3.new(center.X, groundY, center.Z), _plot.faceDir))
	local _, bb = _ghost:GetBoundingBox()
	_ghost:PivotTo(_ghost:GetPivot() + Vector3.new(0, groundY - (_ghost:GetPivot().Position.Y - bb.Y * 0.5), 0))
	local ok = validAt(c.x, c.z)
	local hl = _ghost:FindFirstChildOfClass("Highlight")
	if hl then
		hl.FillColor = ok and GREEN or RED
		hl.OutlineColor = ok and GREEN or RED
	end
	if _ring then
		_ring.Parent = Workspace
		_ring.CFrame = CFrame.new(center.X, groundY + 0.3, center.Z) * CFrame.Angles(0, 0, math.rad(90))
		_ring.Color = ok and GREEN or RED
	end
	if _postawBtn then
		_postawBtn.Visible = ok
	end
end

-- ── akcje ──
local function place()
	if not _sel or not _cell then return end
	if not validAt(_cell.x, _cell.z) then return end
	local res = Net.get("PlaceUnit"):InvokeServer(_sel.key, _cell.x, _cell.z)
	if res and res.ok then
		-- optymistycznie zmniejsz licznik (InventorySync i tak nadpisze)
		_counts[_sel.key] = math.max(0, (_counts[_sel.key] or 1) - 1)
		if (_counts[_sel.key] or 0) <= 0 then
			_sel = nil
			if _ghost then _ghost:Destroy(); _ghost = nil end
			if _ring then _ring:Destroy(); _ring = nil end
		end
		BuildController._refreshCounter()
		BuildController._refreshPanel()
	end
end

local function deleteAt()
	local cam = Workspace.CurrentCamera
	local mp = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mp.X, mp.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local units = Workspace:FindFirstChild("WR_Units")
	if not units then return end
	params.FilterDescendantsInstances = { units }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 800, params)
	if hit then
		local m = hit.Instance:FindFirstAncestorWhichIsA("Model")
		if m and m:GetAttribute("OwnerUserId") == LP.UserId and m:GetAttribute("PlacementId") then
			Net.get("RemoveUnit"):InvokeServer(m:GetAttribute("PlacementId"))
			BuildController._refreshCounter()
		end
	end
end

local function clearPlot()
	local units = Workspace:FindFirstChild("WR_Units")
	if not units then return end
	for _, m in ipairs(units:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("OwnerUserId") == LP.UserId and m:GetAttribute("PlacementId") then
			Net.get("RemoveUnit"):InvokeServer(m:GetAttribute("PlacementId"))
		end
	end
	BuildController._refreshCounter()
end

-- ── UI ──
local function thumb(unitId)
	if _thumbCache[unitId] then return _thumbCache[unitId]:Clone() end
	local vpf = Instance.new("ViewportFrame")
	vpf.BackgroundTransparency = 1
	local tmpl = UnitModelFactory.get(unitId)
	if tmpl then
		local cam = Instance.new("Camera"); vpf.CurrentCamera = cam; cam.Parent = vpf
		local m = tmpl:Clone(); m.Parent = vpf
		local cf, size = m:GetBoundingBox()
		local dist = math.max(size.X, size.Y, size.Z) * 1.6
		cam.CFrame = CFrame.new(cf.Position + Vector3.new(dist * 0.6, size.Y * 0.3, dist), cf.Position)
	end
	_thumbCache[unitId] = vpf
	return vpf:Clone()
end

function BuildController._refreshCounter()
	if not _counter then return end
	local _, used = occupancy()
	_counter.Text = ("%d / %d"):format(used, _budget)
end

function BuildController._refreshPanel()
	if not _grid then return end
	for _, ch in ipairs(_grid:GetChildren()) do
		if ch:IsA("GuiObject") then ch:Destroy() end
	end
	-- posortuj klucze wg nazwy dla stabilnosci
	local keys = {}
	for k, n in pairs(_counts) do
		if n > 0 then keys[#keys + 1] = k end
	end
	table.sort(keys)
	local col, cw, ch, gap, i = 3, 96, 96, 6, 0
	for _, key in ipairs(keys) do
		local unitId = string.split(key, "#")[1]
		local u = GameConfig.Units[unitId]
		if u then
			-- klasyfikacja: bron = ma combat, blok = nie ma combat
			local want = (_activeTab == "weapon") and (u.combat ~= nil) or (_activeTab == "block") and (u.combat == nil)
			if want then
				local cx, cz = i % col, math.floor(i / col)
				local card = Instance.new("TextButton")
				card.Size = UDim2.fromOffset(cw, ch); card.Position = UDim2.fromOffset(cx * (cw + gap), cz * (ch + gap))
				card.BackgroundColor3 = (_sel and _sel.key == key) and Color3.fromRGB(70, 110, 80) or Color3.fromRGB(40, 40, 52)
				card.Text = ""; card.AutoButtonColor = true; card.Parent = _grid
				local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = card
				local tv = thumb(unitId); tv.Size = UDim2.fromScale(1, 0.66); tv.Position = UDim2.fromScale(0, 0.02); tv.Parent = card
				local nm = Instance.new("TextLabel"); nm.Size = UDim2.fromScale(1, 0.2); nm.Position = UDim2.fromScale(0, 0.66)
				nm.BackgroundTransparency = 1; nm.TextColor3 = Color3.new(1, 1, 1); nm.Font = Enum.Font.Gotham; nm.TextScaled = true
				nm.Text = u.displayName or unitId; nm.Parent = card
				local cnt = Instance.new("TextLabel"); cnt.Size = UDim2.fromScale(1, 0.16); cnt.Position = UDim2.fromScale(0, 0.84)
				cnt.BackgroundTransparency = 1; cnt.TextColor3 = Color3.fromRGB(255, 220, 120); cnt.Font = Enum.Font.GothamBold; cnt.TextScaled = true
				cnt.Text = tostring(_counts[key]) .. "x"; cnt.Parent = card
				card.MouseButton1Click:Connect(function()
					_sel = { key = key, unitId = unitId, fp = u.footprint, isWeapon = u.combat ~= nil, range = u.combat and u.combat.range }
					_mode = "place"
					makeGhost()
					BuildController._refreshPanel()
				end)
				i += 1
			end
		end
	end
	_grid.CanvasSize = UDim2.fromOffset(0, math.ceil(i / col) * (ch + gap))
end

local function setTab(t)
	_activeTab = t
	for id, b in pairs(_tabBtns) do
		b.BackgroundColor3 = (id == t) and Color3.fromRGB(70, 90, 120) or Color3.fromRGB(45, 45, 58)
	end
	BuildController._refreshPanel()
end

local function openBuild()
	_on = true
	_mode = "place"
	local info = Net.get("GetPlotInfo"):InvokeServer()
	if info then _plot = info end
	local inv = Net.get("GetInventory"):InvokeServer()
	if inv then _counts = inv end
	_panel.Visible = true
	setTab(_activeTab)
	BuildController._refreshCounter()
end

local function closeBuild()
	_on = false
	_sel = nil
	if _ghost then _ghost:Destroy(); _ghost = nil end
	if _ring then _ring:Destroy(); _ring = nil end
	_panel.Visible = false
end

function BuildController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_Build"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 30
	gui.Parent = LP:WaitForChild("PlayerGui")

	-- przycisk ZBUDUJ (dol, na lewo od ROLL)
	local openBtn = Instance.new("TextButton")
	openBtn.Size = UDim2.fromOffset(140, 54); openBtn.AnchorPoint = Vector2.new(1, 1)
	openBtn.Position = UDim2.new(0.5, -130, 1, -32)
	openBtn.BackgroundColor3 = Color3.fromRGB(70, 100, 60); openBtn.TextColor3 = Color3.new(1, 1, 1)
	openBtn.Font = Enum.Font.GothamBold; openBtn.TextSize = 16; openBtn.Text = "🔨 ZBUDUJ"; openBtn.Parent = gui
	local oc = Instance.new("UICorner"); oc.CornerRadius = UDim.new(0, 10); oc.Parent = openBtn

	-- panel budowania (lewa)
	_panel = Instance.new("Frame")
	_panel.Size = UDim2.fromOffset(330, 470); _panel.Position = UDim2.fromOffset(12, 60)
	_panel.BackgroundColor3 = Color3.fromRGB(20, 20, 28); _panel.BorderSizePixel = 0; _panel.Visible = false; _panel.Parent = gui
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 10); pc.Parent = _panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromOffset(220, 30); title.Position = UDim2.fromOffset(12, 8); title.BackgroundTransparency = 1
	title.TextColor3 = Color3.new(1, 1, 1); title.Font = Enum.Font.GothamBold; title.TextSize = 18; title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "🔨 TRYB BUDOWANIA"; title.Parent = _panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(30, 30); closeBtn.Position = UDim2.new(1, -38, 0, 8)
	closeBtn.BackgroundColor3 = Color3.fromRGB(170, 45, 45); closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 16; closeBtn.Text = "X"; closeBtn.Parent = _panel
	closeBtn.MouseButton1Click:Connect(closeBuild)

	-- zakladki
	_tabBtns = {}
	local tabs = { { "block", "BLOKI" }, { "weapon", "BROŃ" } }
	for i, t in ipairs(tabs) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(150, 34); b.Position = UDim2.fromOffset(12 + (i - 1) * 156, 46)
		b.BackgroundColor3 = Color3.fromRGB(45, 45, 58); b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold; b.TextSize = 15; b.Text = t[2]; b.Parent = _panel
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = b
		_tabBtns[t[1]] = b
		b.MouseButton1Click:Connect(function() setTab(t[1]) end)
	end

	_grid = Instance.new("ScrollingFrame")
	_grid.Size = UDim2.fromOffset(310, 320); _grid.Position = UDim2.fromOffset(12, 88)
	_grid.BackgroundTransparency = 1; _grid.BorderSizePixel = 0; _grid.ScrollBarThickness = 5
	_grid.CanvasSize = UDim2.new(); _grid.Parent = _panel

	local clearBtn = Instance.new("TextButton")
	clearBtn.Size = UDim2.fromOffset(150, 34); clearBtn.Position = UDim2.fromOffset(12, 420)
	clearBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 50); clearBtn.TextColor3 = Color3.new(1, 1, 1)
	clearBtn.Font = Enum.Font.GothamBold; clearBtn.TextSize = 14; clearBtn.Text = "Wyczyść działkę"; clearBtn.Parent = _panel
	local clc = Instance.new("UICorner"); clc.CornerRadius = UDim.new(0, 8); clc.Parent = clearBtn
	clearBtn.MouseButton1Click:Connect(clearPlot)

	_delBtn = Instance.new("TextButton")
	_delBtn.Size = UDim2.fromOffset(140, 34); _delBtn.Position = UDim2.fromOffset(178, 420)
	_delBtn.BackgroundColor3 = Color3.fromRGB(90, 70, 40); _delBtn.TextColor3 = Color3.new(1, 1, 1)
	_delBtn.Font = Enum.Font.GothamBold; _delBtn.TextSize = 14; _delBtn.Text = "🗑 Usuń"; _delBtn.Parent = _panel
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(0, 8); dc.Parent = _delBtn
	_delBtn.MouseButton1Click:Connect(function()
		_mode = (_mode == "delete") and "place" or "delete"
		_delBtn.BackgroundColor3 = (_mode == "delete") and Color3.fromRGB(180, 60, 40) or Color3.fromRGB(90, 70, 40)
		if _mode == "delete" and _ghost then _ghost.Parent = nil; if _ring then _ring.Parent = nil end end
	end)

	-- licznik zajetych kratek (dol-srodek)
	_counter = Instance.new("TextLabel")
	_counter.Size = UDim2.fromOffset(120, 34); _counter.AnchorPoint = Vector2.new(0.5, 1); _counter.Position = UDim2.new(0.5, 0, 1, -96)
	_counter.BackgroundColor3 = Color3.fromRGB(20, 20, 28); _counter.BackgroundTransparency = 0.3
	_counter.TextColor3 = Color3.new(1, 1, 1); _counter.Font = Enum.Font.GothamBold; _counter.TextSize = 20; _counter.Text = "0 / 40"
	_counter.Visible = false; _counter.Parent = gui
	local ctc = Instance.new("UICorner"); ctc.CornerRadius = UDim.new(0, 8); ctc.Parent = _counter

	-- przycisk POSTAW (mobilny confirm; pojawia sie gdy kratka valid)
	_postawBtn = Instance.new("TextButton")
	_postawBtn.Size = UDim2.fromOffset(170, 48); _postawBtn.AnchorPoint = Vector2.new(0.5, 1); _postawBtn.Position = UDim2.new(0.5, 200, 1, -30)
	_postawBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 70); _postawBtn.TextColor3 = Color3.new(1, 1, 1)
	_postawBtn.Font = Enum.Font.GothamBold; _postawBtn.TextSize = 18; _postawBtn.Text = "POSTAW ✓"; _postawBtn.Visible = false; _postawBtn.Parent = gui
	local pbc = Instance.new("UICorner"); pbc.CornerRadius = UDim.new(0, 10); pbc.Parent = _postawBtn
	_postawBtn.MouseButton1Click:Connect(place)

	local function doToggle()
		if _on then closeBuild() else openBuild() end
	end
	BuildController.Toggle = doToggle -- HUD ziomka (SideButtons.Build) wola to
	openBtn.Visible = false -- stary temp guzik ukryty; nasz panel budowania zostaje (Etap E: designerowy BuildMode)
	openBtn.MouseButton1Click:Connect(doToggle)

	-- licznik/postaw widoczne tylko w trybie
	local function syncVis()
		_counter.Visible = _on
		if not _on then _postawBtn.Visible = false end
	end

	-- input: klik na siatce (PC) stawia/usuwa; X anuluje
	UserInputService.InputBegan:Connect(function(input, gp)
		if not _on or gp then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if _mode == "delete" then
				deleteAt()
			elseif _sel and _cell and validAt(_cell.x, _cell.z) then
				place()
			end
		elseif input.KeyCode == Enum.KeyCode.X then
			_sel = nil
			if _ghost then _ghost:Destroy(); _ghost = nil end
			if _ring then _ring:Destroy(); _ring = nil end
		end
	end)

	-- live inventory
	Net.get("InventorySync").OnClientEvent:Connect(function(counts)
		if type(counts) == "table" then
			_counts = counts
			if _on then BuildController._refreshPanel() end
		end
	end)

	-- petla: ghost sledzi kursor + odswieza licznik
	RunService.RenderStepped:Connect(function()
		syncVis()
		if _on and _mode == "place" and _sel and _ghost then
			updateGhost()
		elseif _postawBtn then
			_postawBtn.Visible = false
		end
	end)
end

return BuildController
