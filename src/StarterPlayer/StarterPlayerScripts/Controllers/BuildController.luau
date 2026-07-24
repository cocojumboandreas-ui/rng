--!nonstrict
-- StarterPlayerScripts/Controllers/BuildController.luau  (KLIENT — tryb budowania, wzor: bud.mp4)
-- ZBUDUJ -> panel po lewej (Bloki/Bron ziomka) + GHOST na kratce pod kursorem, ktory PLYNNIE dojezdza
-- (lerp) i wpasowuje sie dokladnie w obrys kratki. Obrys = Highlight (jak podswietlenie Start Wave) pulsujacy
-- na zielono/czerwono (mozna/nie mozna). Celownik (crosshair) rysowany w GUI zamiast kursora systemowego.
-- INTERAKCJE:
--   • Klik karty -> wybor przedmiotu z inventory (ghost sledzi kursor).
--   • LPM na kratce -> POSTAW (PlaceUnit z obrotem rot).
--   • LPM na WLASNEJ postawionej jednostce (gdy nic nie wybrane) -> PODNIES i przenies (MoveUnit, bez ruszania inventory).
--   • R -> obrot o 90° (kosmetyka renderu). X -> anuluj wybor/przenoszenie.
--   • Tryb Usun (Delete) -> LPM/PPM na jednostce usuwa. PPM zawsze usuwa jednostke pod kursorem.
--   • Wyczysc dzialke -> 2-krok (Czy jestes pewny?) -> ClearPlot usuwa WSZYSTKO naraz.
-- Serwer autorytatywny: klient wysyla tylko intencje; walidacja i tak po stronie serwera.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
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
local WHITE = Color3.fromRGB(255, 255, 255) -- obrys jak przy najechaniu na Start Wave (bialy, swiecacy)
local FIT_MARGIN = 0.8 -- MUSI zgadzac sie z BuildService.FIT_MARGIN (ghost == realny model)
local LERP = 0.35 -- plynnosc dojazdu ghosta (0..1; wiecej = szybciej)

-- ── stan ──
local _on = false
local _mode = "place" -- place | delete
local _counts = {} -- invKey -> count (inventory)
local _plot = nil -- {plotId, gridOrigin(CFrame), width, depth, cellSize, faceDir}
local _budget = GameConfig.Grid.baseCellBudget
local _sel = nil -- { key, unitId, fp, isWeapon, range }
local _rot = 0 -- reczny obrot yaw (0/90/180/270), utrzymywany miedzy postawieniami
local _moving = nil -- placementId przenoszonej jednostki (nil = stawiamy nowa z inventory)
local _movingModel = nil -- oryginalny model schowany podczas przenoszenia
local _ghost, _ring = nil, nil
local _ghostPos = nil -- Vector3 lerpowanej pozycji ghosta
local _cell = nil -- {x,z} aktualna kratka pod kursorem
local _hovered = nil -- WLASNA jednostka pod kursorem (podswietlona do edycji, gdy nic nie stawiamy)
local _coreSet = {} -- kratki rdzenia (nie mozna tam stawiac) — z GetPlotInfo.coreCells
local _thumbCache = {}

-- UI refs — designerowy BuildMode (place-owned)
local _bm, _list, _template, _content = nil, nil, nil, nil
local _counter, _tabBtns = nil, nil
local fitListRows -- forward-decl (uzywane w _refreshPanel, definiowane nizej)
local _slotsLbl = nil -- biala liczba slotow ziomka (BuildMode.BottomCanvas.Value)
local _pcControls = nil -- BottomRightCanvas.PcControls (Place/Rotate/Cancel — pokaz tylko gdy stawiamy)
local _activeTab = "weapon"

-- crosshair (celownik) + pulsujacy obrys
local _cursorGui, _reticle, _cursorTint = nil, nil, {}

-- clear-plot 2-krok
local _clearBtn, _clearLbl, _clearArmed, _clearToken = nil, nil, false, 0
local _clearOrigText = "Wyczyść działkę!" -- oryginalny napis przycisku (przywracany po confirm)

-- ── geometria kratek ──
local function cellKey(x, z) return x .. "," .. z end

-- zajetosc wlasnego plotu (opcjonalnie pomijamy jedna jednostke — przy przenoszeniu nie koliduje sama ze soba)
local function occupancy(ignorePid)
	local occ, used = {}, 0
	local units = Workspace:FindFirstChild("WR_Units")
	if units then
		for _, m in ipairs(units:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("OwnerUserId") == LP.UserId then
				if not (ignorePid and m:GetAttribute("PlacementId") == ignorePid) then
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
	end
	return occ, used
end

-- PLATFORMA = blok (nie bron, nie pulapka) -> mozna na niej stawiac kolejne rzeczy
local function isPlatform(unitId)
	local u = unitId and GameConfig.Units[unitId]
	return u ~= nil and u.combat == nil and u.category ~= "trap"
end

-- mapy warstw per-kratka: cellKey -> { [layer] = unitId } (z WR_Units, atrybut Layer). Opcjonalnie pomija _moving.
local function cellLayerMaps(ignorePid)
	local out = {}
	local units = Workspace:FindFirstChild("WR_Units")
	if units then
		for _, m in ipairs(units:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("OwnerUserId") == LP.UserId then
				if not (ignorePid and m:GetAttribute("PlacementId") == ignorePid) then
					local x, z = m:GetAttribute("CellX"), m:GetAttribute("CellZ")
					local w, d = m:GetAttribute("FpW") or 1, m:GetAttribute("FpD") or 1
					local layer = m:GetAttribute("Layer") or 0
					local uid = m:GetAttribute("UnitId")
					if x and z then
						for _, c in ipairs(GridMath.footprintCells(x, z, { w = w, d = d })) do
							local k = cellKey(c.x, c.z)
							out[k] = out[k] or {}
							out[k][layer] = uid
						end
					end
				end
			end
		end
	end
	return out
end

-- NAJNIZSZA warstwa L gdzie footprint sie zmiesci. Wszystkie kratki wolne na L, i (L==0 albo pod kazda na L-1
-- stoi platforma). DZIURE (cos NAD L) wypelnia TYLKO blok; bron/pulapka szuka wyzej. nil = brak. Jak serwer.
local function placementLayer(maps, cells, unitIsPlatform)
	local maxH = 0
	for _, c in ipairs(cells) do
		local m = maps[cellKey(c.x, c.z)]
		if m then for l in pairs(m) do if l + 1 > maxH then maxH = l + 1 end end end
	end
	for L = 0, maxH do
		local ok = true
		for _, c in ipairs(cells) do
			local m = maps[cellKey(c.x, c.z)]
			if m and m[L] ~= nil then ok = false; break end
			if L > 0 then
				local below = m and m[L - 1]
				if not (below and isPlatform(below)) then ok = false; break end
			end
		end
		if ok then
			local hasAbove = false
			if not unitIsPlatform then
				for _, c in ipairs(cells) do
					local m = maps[cellKey(c.x, c.z)]
					if m then for l in pairs(m) do if l > L then hasAbove = true; break end end end
					if hasAbove then break end
				end
			end
			if not hasAbove then return L end
		end
	end
	return nil
end

-- warstwa, na ktora TRAFI wybrana jednostka pod (x,z) — do pozycji Y ghosta (moze wypelnic dziure!).
-- Gdy nie da sie postawic (nil), ghost siedzi na WIERZCHU stosu (czerwony), nie zatapia sie do ziemi.
local function heightAt(x, z)
	if not _sel then return 0 end
	local maps = cellLayerMaps(_moving)
	local cells = GridMath.footprintCells(x, z, _sel.fp)
	local L = placementLayer(maps, cells, isPlatform(_sel.unitId))
	if L then return L end
	local top = 0
	for _, c in ipairs(cells) do
		local m = maps[cellKey(c.x, c.z)]
		if m then for l in pairs(m) do if l + 1 > top then top = l + 1 end end end
	end
	return top
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
	-- CLAMP do siatki (z uwzglednieniem footprintu) — NIE wyjezdzamy poza obrys planszy; ghost zostaje
	-- na ostatnim dostepnym polu przy krawedzi, zamiast znikac gdy kursor wyjedzie poza plansze.
	local w, d = 1, 1
	if _sel then w, d = _sel.fp.w, _sel.fp.d end
	x = math.clamp(x, 1, math.max(1, _plot.width - w + 1))
	z = math.clamp(z, 1, math.max(1, _plot.depth - d + 1))
	return { x = x, z = z }
end

local function validAt(x, z)
	if not _sel then return false end
	local fp = _sel.fp
	local cells = GridMath.footprintCells(x, z, fp)
	-- granice + rdzen
	for _, c in ipairs(cells) do
		if c.x < 1 or c.x > _plot.width or c.z < 1 or c.z > _plot.depth then return false end
		if _coreSet[cellKey(c.x, c.z)] then return false end -- kratka rdzenia
	end
	-- STOS: musi istniec warstwa (dziure wypelni tylko blok; bron/pulapka idzie na wierzch)
	if placementLayer(cellLayerMaps(_moving), cells, isPlatform(_sel.unitId)) == nil then return false end
	-- budzet
	local _, used = occupancy(_moving)
	if used + fp.w * fp.d > _budget then return false end
	return true
end

-- ── ghost + kolo zasiegu ──
local function orientAt(pos, groundY)
	return CFrame.lookAlong(Vector3.new(pos.X, groundY, pos.Z), _plot.faceDir) * CFrame.Angles(0, math.rad(_rot), 0)
end

local function clearGhost()
	if _ghost then _ghost:Destroy(); _ghost = nil end
	if _ring then _ring:Destroy(); _ring = nil end
	_ghostPos = nil
end

-- Buduje ghost DOKLADNIE tak jak serwer stawia model (orientacja faceDir*rot -> pomiar -> skala FIT_MARGIN ->
-- domiar), dzieki czemu podglad = realny model i idealnie miesci sie w obrysie kratki.
local function makeGhost()
	clearGhost()
	if not _sel then return end
	local tmpl = UnitModelFactory.get(_sel.unitId)
	if not tmpl then return end
	local g = tmpl:Clone()
	if not g.PrimaryPart then
		g.PrimaryPart = g:FindFirstChild("HumanoidRootPart") or g:FindFirstChildWhichIsA("BasePart")
	end
	local cs = _plot.cellSize
	local cellW, cellD = _sel.fp.w * cs, _sel.fp.d * cs
	-- orientacja jak na serwerze (mierzymy footprint po obrocie)
	g:PivotTo(CFrame.lookAlong(Vector3.zero, _plot.faceDir) * CFrame.Angles(0, math.rad(_rot), 0))
	-- BLOK (bez broni): pojedynczy Part -> KOSTKA wypelniajaca kratke o wysokosci warstwy (cs), jak na serwerze.
	local blockParts = {}
	if not _sel.isWeapon then
		for _, d in ipairs(g:GetDescendants()) do if d:IsA("BasePart") then blockParts[#blockParts + 1] = d end end
	end
	if not _sel.isWeapon and #blockParts == 1 then
		blockParts[1].Size = Vector3.new(cellW * 0.95, cs, cellD * 0.95)
	else
		local size = g:GetExtentsSize()
		local factor = math.min(cellW / math.max(size.X, 0.01), cellD / math.max(size.Z, 0.01)) * FIT_MARGIN
		factor = math.min(factor, 1)
		if factor < 0.999 and g.ScaleTo then g:ScaleTo(factor) end
		if g.GetScale and g.ScaleTo then -- gwarancja zmieszczenia (dlugie pojazdy)
			local s2 = g:GetExtentsSize()
			local over = math.max(s2.X / cellW, s2.Z / cellD)
			if over > 1 then g:ScaleTo(g:GetScale() / over * 0.98) end
		end
	end
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false end
	end
	g.Parent = Workspace
	_ghost = g
	-- OBRYS jak przy najechaniu na Start Wave: Highlight obrysowuje DOKLADNY ksztalt modelu bialym,
	-- swiecacym konturem (pulsuje w petli renderu). Wypelnienie ledwo widoczne — liczy sie kontur.
	local hl = Instance.new("Highlight")
	hl.Adornee = g
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillColor = GREEN
	hl.FillTransparency = 0.8
	hl.OutlineColor = WHITE
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
	_ghostPos = nil -- nastepna klatka snapuje na kratke (bez dojazdu z poprzedniego miejsca)
end

local function updateGhost()
	if not _ghost or not _plot then return end
	local c = cursorCell()
	if c then _cell = c end -- ray trafil w plaszczyzne -> zaktualizuj (clamped). Miss (sky) -> zostaw ostatnia kratke.
	if not _cell then
		-- jeszcze nigdy nie bylo kratki (start) -> schowaj do pierwszego trafienia
		_ghost.Parent = nil
		if _ring then _ring.Parent = nil end
		return
	end
	_ghost.Parent = Workspace
	local center = GridMath.cellToWorld(_plot.gridOrigin, _plot.cellSize, _cell.x, _cell.z, _sel.fp).Position
	local groundY = _plot.gridOrigin.Position.Y
	local surfaceY = groundY + heightAt(_cell.x, _cell.z) * _plot.cellSize -- STACK: siada na wierzchu stosu
	local targetPos = Vector3.new(center.X, groundY, center.Z)
	_ghostPos = _ghostPos and _ghostPos:Lerp(targetPos, LERP) or targetPos
	-- pozycja (plynnie) + orientacja (natychmiast, wg _rot), potem posadz na WIERZCHU stosu (surfaceY)
	_ghost:PivotTo(orientAt(_ghostPos, groundY))
	local bbCf, bbSize = _ghost:GetBoundingBox()
	_ghost:PivotTo(_ghost:GetPivot() + Vector3.new(0, surfaceY - (bbCf.Position.Y - bbSize.Y * 0.5), 0))
	-- RECENTER XZ: STOPY (HumanoidRootPart) w srodek kratki — nie pistolet/bbox. Dla blokow/pojazdow: srodek bbox.
	local anchor = _ghost:FindFirstChild("HumanoidRootPart", true)
	local aPos = (anchor and anchor:IsA("BasePart")) and anchor.Position or (select(1, _ghost:GetBoundingBox())).Position
	_ghost:PivotTo(_ghost:GetPivot() + Vector3.new(_ghostPos.X - aPos.X, 0, _ghostPos.Z - aPos.Z))
	local ok = validAt(_cell.x, _cell.z)
	local hl = _ghost:FindFirstChildOfClass("Highlight")
	if hl then
		-- OK = bialy obrys (jak Start Wave), zle miejsce = czerwony
		hl.FillColor = ok and GREEN or RED
		hl.OutlineColor = ok and WHITE or RED
	end
	if _ring then
		_ring.Parent = Workspace
		_ring.CFrame = CFrame.new(_ghostPos.X, surfaceY + 0.3, _ghostPos.Z) * CFrame.Angles(0, 0, math.rad(90))
		_ring.Color = ok and GREEN or RED
	end
end

-- ── celownik (crosshair) ──
local function makeCursor()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_BuildCursor"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200000; gui.Enabled = false; gui.Parent = LP:WaitForChild("PlayerGui")

	local ret = Instance.new("Frame")
	ret.Name = "Reticle"; ret.Size = UDim2.fromOffset(46, 46); ret.AnchorPoint = Vector2.new(0.5, 0.5)
	ret.BackgroundTransparency = 1; ret.Parent = gui

	local function stroke(parent, thick)
		local s = Instance.new("UIStroke")
		s.Thickness = thick; s.Color = Color3.new(1, 1, 1); s.Transparency = 0
		s.Parent = parent
		_cursorTint[#_cursorTint + 1] = s
		return s
	end

	-- pierscien
	local ring = Instance.new("Frame")
	ring.Size = UDim2.fromOffset(30, 30); ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5); ring.BackgroundTransparency = 1; ring.Parent = ret
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = ring
	stroke(ring, 2)

	-- 4 kreski (N/S/E/W)
	local ticks = {
		{ UDim2.fromOffset(3, 9), UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 0) }, -- gora
		{ UDim2.fromOffset(3, 9), UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 1) }, -- dol
		{ UDim2.fromOffset(9, 3), UDim2.new(0, 0, 0.5, 0), Vector2.new(0, 0.5) }, -- lewo
		{ UDim2.fromOffset(9, 3), UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5) }, -- prawo
	}
	for _, t in ipairs(ticks) do
		local bar = Instance.new("Frame")
		bar.Size = t[1]; bar.Position = t[2]; bar.AnchorPoint = t[3]
		bar.BackgroundColor3 = Color3.new(1, 1, 1); bar.BorderSizePixel = 0; bar.Parent = ret
		stroke(bar, 1)
	end

	-- kropka srodkowa
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(4, 4); dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5); dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BorderSizePixel = 0; dot.Parent = ret
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot

	_cursorGui, _reticle = gui, ret
end

local function tintCursor(color)
	for _, s in ipairs(_cursorTint) do s.Color = color end
end

-- Celownik (marker nad jednostka) wl/wyl. Myszka SYSTEMOWA zostaje DOMYSLNA (nigdy nie chowamy) —
-- celownik to tylko znacznik nad ghostem, a normalna strzalka pozwala klikac UI/karty.
local function setCursor(active)
	if _cursorGui then _cursorGui.Enabled = active end
end

local function setPcControls(vis)
	if _pcControls then _pcControls.Visible = vis end
end

-- ── akcje ──
local function place()
	if not _sel or not _cell then return end
	if not validAt(_cell.x, _cell.z) then return end
	if _moving then
		-- przenoszenie juz postawionej jednostki (bez zwrotu do inventory)
		local res = Net.get("MoveUnit"):InvokeServer(_moving, _cell.x, _cell.z, _rot)
		if res and res.ok then
			_moving = nil; _movingModel = nil -- serwer zniszczyl stary i postawil nowy model
			_sel = nil
			clearGhost()
			setPcControls(false); setCursor(false)
			BuildController._refreshCounter()
		end
		return
	end
	local res = Net.get("PlaceUnit"):InvokeServer(_sel.key, _cell.x, _cell.z, _rot)
	if res and res.ok then
		_counts[_sel.key] = math.max(0, (_counts[_sel.key] or 1) - 1)
		if (_counts[_sel.key] or 0) <= 0 then
			_sel = nil
			clearGhost()
			setPcControls(false); setCursor(false)
		end
		BuildController._refreshCounter()
		BuildController._refreshPanel()
	end
end

-- raycast do WLASNEJ jednostki pod kursorem -> Model (albo nil)
local function unitUnderCursor()
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local mp = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mp.X, mp.Y)
	local units = Workspace:FindFirstChild("WR_Units")
	if not units then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { units }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 800, params)
	if not hit then return nil end
	-- wejdz w GORE do jednostki po atrybucie PlacementId (ma go KAZDY postawiony block i weapon — ustawiany
	-- w BuildService.spawnModel). Dziala uniwersalnie: piechota, bloki, dziala/mozdzierze, pojazdy. Przeskakuje
	-- zagniezdzone modele (np. kierowca Jeepa = WR_Driver bez PlacementId), na ktore FindFirstAncestor by trafial.
	local m = hit.Instance
	while m and m:GetAttribute("PlacementId") == nil do
		m = m.Parent
	end
	if m and m:GetAttribute("OwnerUserId") == LP.UserId then
		return m
	end
	return nil
end

-- HOVER-do-edycji: gdy nic nie stawiamy, jednostka pod kursorem dostaje bialy obrys (jak Start Wave)
-- + lekkie przyciemnienie (czarny fill) — sygnal "kliknij, by ja edytowac/przestawic". Efekt lokalny.
local function clearHover()
	if _hovered and _hovered.Parent then
		local h = _hovered:FindFirstChild("WR_HoverHL")
		if h then h:Destroy() end
	end
	_hovered = nil
end

local function updateHover()
	local m = unitUnderCursor()
	if m == _hovered then return end
	clearHover()
	if m then
		local hl = Instance.new("Highlight")
		hl.Name = "WR_HoverHL"
		hl.Adornee = m
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.OutlineColor = WHITE
		hl.OutlineTransparency = 0
		hl.FillColor = Color3.new(0, 0, 0) -- lekkie przyciemnienie jednostki
		hl.FillTransparency = 0.6
		hl.Parent = m
		_hovered = m
	end
end

local function cancelSelection()
	clearHover()
	if _movingModel then -- odkryj oryginal, zostaje tam gdzie byl
		for _, d in ipairs(_movingModel:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 end
		end
	end
	_moving = nil; _movingModel = nil; _sel = nil
	clearGhost()
	setPcControls(false); setCursor(false)
end

-- podnies wlasna jednostke do przeniesienia
local function pickup(m)
	local unitId = m:GetAttribute("UnitId")
	local u = unitId and GameConfig.Units[unitId]
	if not u then return end
	-- EDYCJA dowolnej jednostki (tez dolnego bloku) — to co na niej stalo zostanie "w powietrzu".
	clearHover() -- zdejmij podswietlenie hover (zaraz schowamy oryginal i zrobimy ghosta)
	_moving = m:GetAttribute("PlacementId")
	_movingModel = m
	_rot = m:GetAttribute("Rot") or 0
	_sel = {
		key = unitId, unitId = unitId, fp = u.footprint,
		isWeapon = u.combat ~= nil,
		range = u.combat and (u.combat.range * (GameConfig.Sim.unitRangeMult or 1)),
	}
	_mode = "place"
	-- schowaj oryginal lokalnie (ghost go zastepuje)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.LocalTransparencyModifier = 1 end
	end
	makeGhost()
	setPcControls(true); setCursor(true)
end

local function deleteAt()
	local m = unitUnderCursor()
	if m then
		Net.get("RemoveUnit"):InvokeServer(m:GetAttribute("PlacementId"))
		BuildController._refreshCounter()
	end
end

-- Wyczysc dzialke: 1. klik uzbraja ("Czy jestes pewny?"), 2. klik czysci naraz (ClearPlot).
local function clearPlot()
	if not _clearArmed then
		_clearArmed = true
		if _clearLbl then _clearLbl.Text = "Czy jesteś pewny?" end
		_clearToken += 1
		local tok = _clearToken
		task.delay(3, function() -- auto-rozbrojenie po 3 s
			if _clearArmed and _clearToken == tok then
				_clearArmed = false
				if _clearLbl then _clearLbl.Text = _clearOrigText end
			end
		end)
		return
	end
	_clearArmed = false
	_clearToken += 1
	if _clearLbl then _clearLbl.Text = _clearOrigText end
	Net.get("ClearPlot"):InvokeServer()
	_sel = nil; _moving = nil; _movingModel = nil
	clearGhost()
	setPcControls(false); setCursor(false)
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
	if _slotsLbl then
		if _slotsLbl:IsA("TextLabel") then _slotsLbl.Text = txt end
		local inner = _slotsLbl:FindFirstChild("Value")
		if inner and inner:IsA("TextLabel") then inner.Text = txt end
	end
	if _counter then _counter.Text = txt end
end

function BuildController._refreshPanel()
	if not _list or not _template then return end
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
			local want = (_activeTab == "weapon") and (u.combat ~= nil) or (_activeTab == "block") and (u.combat == nil)
			if want then
				local card = _template:Clone()
				card.Name = "Card_" .. key
				card.Visible = true
				-- 3 KOLUMNY na sztywno (niezaleznie od rozdzielczosci): szerokosc karty = ~30% SZEROKOSCI listy;
				-- box wysokosci = 100%, wiec UIAspectRatioConstraint (kwadrat) bierze SZEROKOSC jako limit ->
				-- karta zawsze 0.3*listW szeroka -> mieszcza sie dokladnie 3 w rzedzie (a nie 4 na szerszym ekranie).
				card.Size = UDim2.new(0.30, 0, 1, 0)
				local arc = card:FindFirstChildOfClass("UIAspectRatioConstraint")
				if arc then arc.DominantAxis = Enum.DominantAxis.Width end
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
				local petIcon = card:FindFirstChild("PetIcon")
				if petIcon then
					petIcon.Image = ""
					local tv = thumb(unitId); tv.Size = UDim2.fromScale(1, 1); tv.Position = UDim2.fromScale(0, 0); tv.Parent = petIcon
				end
				local st = card:FindFirstChildOfClass("UIStroke")
				if st then st.Enabled = (_sel and not _moving and _sel.key == key) or false end
				card.MouseButton1Click:Connect(function()
					_moving = nil; _movingModel = nil
					_sel = { key = key, unitId = unitId, fp = u.footprint, isWeapon = u.combat ~= nil, range = u.combat and (u.combat.range * (GameConfig.Sim.unitRangeMult or 1)) }
					_mode = "place"
					makeGhost()
					setPcControls(true); setCursor(true)
					BuildController._refreshPanel()
				end)
				card.Parent = _list
			end
		end
	end
	-- po zbudowaniu kart: przytnij widok listy do CALYCH rzedow (zaden napis nie jest przeciety obrysem)
	task.defer(function()
		RunService.Heartbeat:Wait()
		fitListRows()
	end)
end

-- Dopasuj WYSOKOSC widoku listy do calej liczby rzedow (karty wrap 3-w-rzedzie). Karty sa kwadratowe i
-- skalowane od SZEROKOSCI (UIAspectRatioConstraint, dominant=Width), wiec zmiana wysokosci NIE rusza ich
-- rozmiaru — tylko ucina widok na granicy rzedu, zeby zaden napis (x8/nazwa) nie byl przeciety obrysem.
-- Nadmiar rzedow chowa sie i mozna do niego zjechac (scroll). Skala-odporne (liczone z realnych rozmiarow).
function fitListRows()
	if not (_list and _content) then return end
	local layout, card
	for _, c in ipairs(_list:GetChildren()) do
		if c:IsA("UIListLayout") then layout = c end
		if not card and c:IsA("GuiButton") then card = c end
	end
	if not (layout and card) then return end
	local cardH = card.AbsoluteSize.Y
	if cardH < 1 then return end
	local padY = layout.Padding.Offset
	local pitch = cardH + padY
	local avail = _content.AbsoluteSize.Y
	local rows = math.max(1, math.floor((avail + padY) / pitch + 1e-3))
	local wholeH = rows * cardH + (rows - 1) * padY
	_list.Size = UDim2.new(_list.Size.X.Scale, _list.Size.X.Offset, 0, math.floor(wholeH + 0.5))
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

local function setHudHidden(hidden)
	if hidden then HudOverlay.enter(false) else HudOverlay.exit() end
end

local function openBuild()
	_on = true
	_mode = "place"
	UserInputService.MouseIconEnabled = true -- myszka zawsze domyslna w budowaniu (na wypadek starego stanu)
	local info = Net.get("GetPlotInfo"):InvokeServer()
	if info then _plot = info end
	_coreSet = {} -- kratki rdzenia -> ghost czerwony, klik nie postawi
	if _plot and _plot.coreCells then
		for _, cc in ipairs(_plot.coreCells) do _coreSet[cellKey(cc.x, cc.z)] = true end
	end
	local inv = Net.get("GetInventory"):InvokeServer()
	if inv then _counts = inv end
	if _bm then _bm.Enabled = true end
	setPcControls(false)
	setHudHidden(true)
	setTab(_activeTab)
	BuildController._refreshCounter()
end

local function closeBuild()
	_on = false
	cancelSelection()
	_mode = "place"
	if _bm then _bm.Enabled = false end
	setHudHidden(false)
	UserInputService.MouseIconEnabled = true
end

function BuildController.start()
	makeCursor()

	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_Build"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 30
	gui.Parent = LP:WaitForChild("PlayerGui")

	-- DESIGNEROWY panel budowania (StarterGui.BuildMode, place-owned)
	local buildMode = LP:WaitForChild("PlayerGui"):WaitForChild("BuildMode", 15)
	_bm = buildMode
	if buildMode then
		local root = buildMode:FindFirstChild("LeftCanvas") and buildMode.LeftCanvas:FindFirstChild("BuildMode")
		local stroke = root and root:FindFirstChild("ContentStroke")
		local content = stroke and stroke:FindFirstChild("Content")
		_list = content and content:FindFirstChild("List")
		_content = content
		-- SZEROKOSC i uklad kart ZOSTAJA jak u ziomka (karty skalowane od szerokosci - nie ruszamy). Robimy:
		-- (1) klip do obrysu panelu, (2) widok listy przyciety do CALYCH rzedow (fitListRows) -> zaden napis
		-- nie jest przeciety obrysem, (3) pionowy scroll przy duzej ilosci jednostek. ScrollBarThickness=0 ->
		-- pasek nie zweza kanwy, karty dalej pelna szerokosc (scroll kolkiem myszy).
		if stroke then stroke.ClipsDescendants = true end
		if content then
			content.ClipsDescendants = true
			local cl = content:FindFirstChildOfClass("UIListLayout")
			if cl then cl.VerticalAlignment = Enum.VerticalAlignment.Top end -- lista trzyma sie GORY po skroceniu widoku
			content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitListRows) -- rekalkulacja przy zmianie rozdzielczosci
		end
		if _list then
			_list.ClipsDescendants = true
			_list.AutomaticCanvasSize = Enum.AutomaticSize.Y
			_list.ScrollingEnabled = true
			_list.ScrollBarThickness = 0
		end
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
		-- Wyczysc dzialke (2-krok confirm) — deepest TextLabel do zmiany napisu
		_clearBtn = root and root:FindFirstChild("ClearPlot")
		if _clearBtn then
			local tl = _clearBtn:FindFirstChild("TextLabel")
			_clearLbl = tl and tl:FindFirstChild("TextLabel") or tl
			if _clearLbl and _clearLbl:IsA("TextLabel") then _clearOrigText = _clearLbl.Text end
			_clearBtn.MouseButton1Click:Connect(clearPlot)
		end
		-- biala liczba slotow ziomka (BottomCanvas.Value)
		local bc = buildMode:FindFirstChild("BottomCanvas")
		_slotsLbl = bc and bc:FindFirstChild("Value")
		-- Exit/Delete ziomka (Build='Exit', Skills='Delete')
		local bcBtns = bc and bc:FindFirstChild("Buttons")
		local exitB = bcBtns and bcBtns:FindFirstChild("Build")
		local delB = bcBtns and bcBtns:FindFirstChild("Skills")
		if exitB then exitB.MouseButton1Click:Connect(closeBuild) end
		if delB then
			delB.MouseButton1Click:Connect(function()
				_mode = (_mode == "delete") and "place" or "delete"
				if _mode == "delete" then cancelSelection() end
			end)
		end
		-- napis PC (Kliknij-Umiesc / R-Obroc / X-Anuluj) — pokaz tylko gdy cos stawiamy
		local brc = buildMode:FindFirstChild("BottomRightCanvas")
		_pcControls = brc and brc:FindFirstChild("PcControls")
		setPcControls(false)
		buildMode.Enabled = false
	else
		warn("[BuildController] brak StarterGui.BuildMode")
	end

	local function doToggle()
		if _on then closeBuild() else openBuild() end
	end
	BuildController.Toggle = doToggle -- HUD ziomka (SideButtons.Build) wola to

	-- input: LPM stawia/podnosi/usuwa, PPM usuwa, R obraca, X anuluje
	UserInputService.InputBegan:Connect(function(input, gp)
		if not _on then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if gp then return end -- klik w UI panelu (karty) — nie stawiaj
			if _mode == "delete" then
				deleteAt()
			elseif _sel then
				if _cell and validAt(_cell.x, _cell.z) then place() end
			else
				local m = unitUnderCursor() -- nic nie wybrane -> podnies jednostke do przeniesienia
				if m then pickup(m) end
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			-- PPM: gdy cos trzymamy -> anuluj wybor (nie usuwaj cudzej jednostki!); inaczej -> usun pod kursorem
			if not gp then
				if _sel then cancelSelection() else deleteAt() end
			end
		elseif input.KeyCode == Enum.KeyCode.R then
			if _sel then
				_rot = (_rot + 90) % 360
				makeGhost()
			end
		elseif input.KeyCode == Enum.KeyCode.X then
			if _sel then cancelSelection() end
		end
	end)

	-- live inventory
	Net.get("InventorySync").OnClientEvent:Connect(function(counts)
		if type(counts) == "table" then
			_counts = counts
			if _on then BuildController._refreshPanel(); BuildController._refreshCounter() end
		end
	end)

	-- petla: ghost sledzi kursor (plynnie) + celownik pod myszka + pulsujacy obrys
	RunService.RenderStepped:Connect(function(dt)
		if not _on then return end
		if _mode == "place" and _sel and _ghost then
			updateGhost()
		end
		-- celownik: siedzi DOKLADNIE na srodku kratki (rzut world->ekran), a poza siatka — pod myszka.
		-- gui ma IgnoreGuiInset=true, wiec dodajemy GetGuiInset (WorldToViewportPoint/GetMouseLocation sa bez topbara).
		if _sel then
			if _hovered then clearHover() end -- podczas stawiania/przenoszenia nie podswietlamy hover
			-- Celownik = marker NAD jednostka (ghost), rzutowany world->ekran. NIE sledzi myszki i NIE chowa
			-- kursora systemowego (myszka zostaje domyslna, mozna klikac UI). Pokazuje sie tylko gdy ghost jest
			-- widoczny na kratce (a jest zawsze, bo cursorCell clampuje do planszy).
			local cam = Workspace.CurrentCamera
			if _cell and _ghostPos and cam and _ghost then
				local inset = GuiService:GetGuiInset()
				local _, bbSize = _ghost:GetBoundingBox()
				local aboveY = _plot.gridOrigin.Position.Y + bbSize.Y + 2.5
				local sp = cam:WorldToViewportPoint(Vector3.new(_ghostPos.X, aboveY, _ghostPos.Z))
				_reticle.Position = UDim2.fromOffset(sp.X + inset.X, sp.Y + inset.Y)
				_reticle.Rotation = (_reticle.Rotation + dt * 45) % 360 -- powolny obrot (efekt)
				local ok = validAt(_cell.x, _cell.z)
				tintCursor(ok and GREEN or Color3.new(1, 1, 1))
				local hl = _ghost:FindFirstChildOfClass("Highlight")
				if hl then hl.OutlineTransparency = 0.15 + 0.15 * math.abs(math.sin(os.clock() * 3)) end
				if not _cursorGui.Enabled then _cursorGui.Enabled = true end
			else
				if _cursorGui.Enabled then _cursorGui.Enabled = false end
			end
		else
			-- nic nie stawiamy: podswietl wlasna jednostke pod kursorem (klik = edycja/przestawienie).
			-- Tylko w trybie stawiania (w trybie Usun LPM kasuje, wiec bez hover-edycji).
			if _mode == "place" then updateHover() else clearHover() end
			if _cursorGui.Enabled then _cursorGui.Enabled = false end
		end
	end)
end

return BuildController
