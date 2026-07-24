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
local HudOverlay = require(script.Parent:WaitForChild("HudOverlay"))

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

-- UI refs — designerowy BuildMode (StarterGui.BuildMode, place-owned) + male overlaye (WR_Build)
local _bm, _list, _template = nil, nil, nil -- ScreenGui BuildMode / lista / karta-szablon
local _counter, _tabBtns, _postawBtn, _delBtn, _exitBtn = nil, nil, nil, nil, nil
local _slotsLbl = nil -- biala liczba slotow ziomka (BuildMode.BottomCanvas.Value)
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
	local _, used = occupancy()
	local txt = ("%d / %d"):format(used, _budget)
	-- biala liczba slotow ziomka (warstwowy tekst: Value + zagniezdzony Value)
	if _slotsLbl then
		if _slotsLbl:IsA("TextLabel") then _slotsLbl.Text = txt end
		local inner = _slotsLbl:FindFirstChild("Value")
		if inner and inner:IsA("TextLabel") then inner.Text = txt end
	end
	if _counter then _counter.Text = txt end
end

function BuildController._refreshPanel()
	if not _list or not _template then return end
	-- usun poprzednie karty (Template jest juz poza lista -> zostaja tylko klony)
	for _, ch in ipairs(_list:GetChildren()) do
		if ch:IsA("GuiButton") then ch:Destroy() end
	end
	local keys = {}
	for k, n in pairs(_counts) do
		if n > 0 then keys[#keys + 1] = k end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local unitId = string.split(key, "#")[1]
		local u = GameConfig.Units[unitId]
		if u then
			-- klasyfikacja: bron = ma combat, blok = nie ma combat
			local want = (_activeTab == "weapon") and (u.combat ~= nil) or (_activeTab == "block") and (u.combat == nil)
			if want then
				local card = _template:Clone()
				card.Name = "Card_" .. key
				card.Visible = true
				-- dwa labele "Text": licznik konczy sie na "x", reszta = nazwa
				local nameL, countL
				for _, l in ipairs(card:GetChildren()) do
					if l:IsA("TextLabel") and l.Name == "Text" then
						if tostring(l.Text):match("x%s*$") then countL = l else nameL = l end
					end
				end
				if nameL then nameL.Text = u.displayName or unitId end
				if countL then countL.Text = tostring(_counts[key]) .. "x" end
				local stats = card:FindFirstChild("Stats")
				local atkL = stats and stats:FindFirstChild("Attack") and stats.Attack:FindFirstChild("TextLabel")
				local hpL = stats and stats:FindFirstChild("Health") and stats.Health:FindFirstChild("TextLabel")
				if atkL then atkL.Text = u.combat and ("⚔️ " .. tostring(u.combat.dmg)) or "🧱 blok" end
				if hpL then hpL.Text = "💘 " .. tostring(u.hp or 0) end
				-- miniatura 3D w PetIcon (nasze modele nie maja assetId ikon)
				local petIcon = card:FindFirstChild("PetIcon")
				if petIcon then
					petIcon.Image = ""
					local tv = thumb(unitId); tv.Size = UDim2.fromScale(1, 1); tv.Position = UDim2.fromScale(0, 0); tv.Parent = petIcon
				end
				-- podswietl wybrana (UIStroke jesli szablon ma)
				local st = card:FindFirstChildOfClass("UIStroke")
				if st then st.Enabled = (_sel and _sel.key == key) or false end
				card.MouseButton1Click:Connect(function()
					_sel = { key = key, unitId = unitId, fp = u.footprint, isWeapon = u.combat ~= nil, range = u.combat and (u.combat.range * (GameConfig.Sim.unitRangeMult or 1)) }
					_mode = "place"
					makeGhost()
					BuildController._refreshPanel()
				end)
				card.Parent = _list
			end
		end
	end
end

local function setTab(t)
	_activeTab = t
	for id, b in pairs(_tabBtns) do
		if b then
			local st = b:FindFirstChildOfClass("UIStroke")
			if st then st.Enabled = (id == t) end
			b.BackgroundTransparency = (id == t) and 0 or 0.4
		end
	end
	BuildController._refreshPanel()
end

-- chowanie HUD-u ziomka w trybie budowania — wspolny HudOverlay (jeden system dla Build/Index/Sklep).
-- keepCoins=false: w budowaniu chowamy tez monety (jak budpw.png).
local function setHudHidden(hidden)
	if hidden then HudOverlay.enter(false) else HudOverlay.exit() end
end

local function openBuild()
	_on = true
	_mode = "place"
	local info = Net.get("GetPlotInfo"):InvokeServer()
	if info then _plot = info end
	local inv = Net.get("GetInventory"):InvokeServer()
	if inv then _counts = inv end
	if _bm then _bm.Enabled = true end
	setHudHidden(true) -- schowaj kostke/Zbuduj/Umiejetnosci/fale/lewe UI/offline (jak budpw.png)
	setTab(_activeTab)
	BuildController._refreshCounter()
end

local function closeBuild()
	_on = false
	_sel = nil
	if _ghost then _ghost:Destroy(); _ghost = nil end
	if _ring then _ring:Destroy(); _ring = nil end
	if _bm then _bm.Enabled = false end
	setHudHidden(false) -- przywroc HUD
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
	openBtn.Font = Enum.Font.GothamBold; openBtn.TextSize = 16; openBtn.Text = " ZBUDUJ"; openBtn.Parent = gui
	local oc = Instance.new("UICorner"); oc.CornerRadius = UDim.new(0, 10); oc.Parent = openBtn

		-- DESIGNEROWY panel budowania (StarterGui.BuildMode, place-owned)
		local buildMode = LP:WaitForChild("PlayerGui"):WaitForChild("BuildMode", 15)
		_bm = buildMode
		if buildMode then
			local root = buildMode:FindFirstChild("LeftCanvas") and buildMode.LeftCanvas:FindFirstChild("BuildMode")
			local stroke = root and root:FindFirstChild("ContentStroke")
			local content = stroke and stroke:FindFirstChild("Content")
			_list = content and content:FindFirstChild("List")
			local tmpl = _list and _list:FindFirstChild("Template")
			if tmpl and content then
				_template = tmpl
				_template.Parent = content
				_template.Visible = false
			end
			local btns = stroke and stroke:FindFirstChild("Buttons")
			_tabBtns = { block = btns and btns:FindFirstChild("Blocks"), weapon = btns and btns:FindFirstChild("Weapons") }
			if _tabBtns.block then _tabBtns.block.MouseButton1Click:Connect(function() setTab("block") end) end
			if _tabBtns.weapon then _tabBtns.weapon.MouseButton1Click:Connect(function() setTab("weapon") end) end
			local xBtn = root and root:FindFirstChild("X")
			if xBtn then xBtn.MouseButton1Click:Connect(closeBuild) end
			local clearB = root and root:FindFirstChild("ClearPlot")
			if clearB then clearB.MouseButton1Click:Connect(clearPlot) end
			-- biala liczba slotow ziomka (BottomCanvas.Value) — nasz licznik ja aktualizuje
			local bc = buildMode:FindFirstChild("BottomCanvas")
			_slotsLbl = bc and bc:FindFirstChild("Value")
			-- Exit/Delete ziomka (wewn. nazwy Build='Exit', Skills='Delete')
			local bcBtns = bc and bc:FindFirstChild("Buttons")
			local exitB = bcBtns and bcBtns:FindFirstChild("Build")
			local delB = bcBtns and bcBtns:FindFirstChild("Skills")
			if exitB then exitB.MouseButton1Click:Connect(closeBuild) end -- Exit -> wyjdz z budowania
			if delB then
				delB.MouseButton1Click:Connect(function() -- Delete -> tryb kasowania (klik jednostki usuwa)
					_mode = (_mode == "delete") and "place" or "delete"
					if _mode == "delete" and _ghost then _ghost.Parent = nil; if _ring then _ring.Parent = nil end end
				end)
			end
			buildMode.Enabled = false
		else
			warn("[BuildController] brak StarterGui.BuildMode")
		end

	-- Proceduralne Wyjscie/Usun/licznik/POSTAW USUNIETE — uzywamy UI ziomka:
	-- Wyjscie = BuildMode.X, licznik slotow = BuildMode.BottomCanvas.Value, czyszczenie = ClearPlot.
	-- Usuwanie pojedynczej jednostki = PPM na siatce (patrz input nizej).

	local function doToggle()
		if _on then closeBuild() else openBuild() end
	end
	BuildController.Toggle = doToggle -- HUD ziomka (SideButtons.Build) wola to
	openBtn.Visible = false -- stary temp guzik ukryty; nasz panel budowania zostaje (Etap E: designerowy BuildMode)
	openBtn.MouseButton1Click:Connect(doToggle)

	local function syncVis()
		if _postawBtn then _postawBtn.Visible = false end
	end

	-- input: LPM stawia, PPM usuwa jednostke pod kursorem, X anuluje wybor
	UserInputService.InputBegan:Connect(function(input, gp)
		if not _on or gp then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if _mode == "delete" then
				deleteAt()
			elseif _sel and _cell and validAt(_cell.x, _cell.z) then
				place()
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			deleteAt() -- PPM = usun jednostke pod kursorem
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
