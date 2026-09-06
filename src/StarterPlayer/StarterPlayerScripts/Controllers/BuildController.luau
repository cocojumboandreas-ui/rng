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
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GridMath = require(Framework:WaitForChild("GridMath"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitModelFactory = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UnitModelFactory"))
local HudOverlay = require(script.Parent:WaitForChild("HudOverlay"))
local Notify = require(script.Parent:WaitForChild("Notify")) -- wspolny toast przez designerowy Notifications.Template

local BuildController = {}

local LP = Players.LocalPlayer
-- MOBILNY tryb: dotyk bez klawiatury -> pokazujemy przyciski Accept/Rotate/Cancel zamiast podpowiedzi PC.
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local GREEN = Color3.fromRGB(80, 220, 100)
local RED = Color3.fromRGB(220, 70, 70)
local WHITE = Color3.fromRGB(255, 255, 255) -- obrys jak przy najechaniu na Start Wave (bialy, swiecacy)
local FIT_MARGIN = 0.8 -- MUSI zgadzac sie z BuildService.FIT_MARGIN (ghost == realny model)
local LERP = 0.35 -- plynnosc dojazdu ghosta (0..1; wiecej = szybciej)
local POP_SOUND_ID = "rbxassetid://15675055424" -- "Roblox_UI_Cute_Pop", ten sam co RollRevealController

-- 2.9K / 10.0K / 1.2M (statystyki na karcie przy najechaniu)
local function fmtNum(n)
	n = n or 0
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n + 0.5))
end

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
local _ghostPos = nil -- Vector3 lerpowanej pozycji ghosta (XZ + grunt)
local _ghostYaw = nil -- stopnie: lerpowany obrot ghosta (persystuje jak _rot; NIE resetujemy przy makeGhost/R)
local _ghostSurfaceY = nil -- lerpowana wysokosc (siadanie na wierzchu stosu); resetuje sie jak _ghostPos
local _cell = nil -- {x,z} aktualna kratka pod kursorem
local _suppressGhost = false -- mobile: nie przesuwaj ghosta gdy palec dotyka przyciskow Accept/Rotate/Cancel
local _hovered = nil -- WLASNA jednostka pod kursorem (podswietlona do edycji, gdy nic nie stawiamy)
local _coreSet = {} -- kratki rdzenia (nie mozna tam stawiac) — z GetPlotInfo.coreCells
local _thumbCache = {}

-- UI refs — designerowy BuildMode (place-owned)
local _bm, _list, _template, _content = nil, nil, nil, nil
local _counter, _tabBtns = nil, nil
local fitListRows -- forward-decl (uzywane w _refreshPanel, definiowane nizej)
local _slotsLbl = nil -- biala liczba slotow ziomka (BuildMode.BottomCanvas.Value)
local _pcControls = nil -- BottomRightCanvas.PcControls (Place/Rotate/Cancel — pokaz tylko gdy stawiamy)
local _brSaved = {} -- zapamietana widocznosc koniczyny(Luck)+kostki(None) chowanych na czas budowania (user)
local _mobileControls = nil -- BuildMode.MobileControls (dotykowe Accept/Rotate/Cancel — tylko na telefonie)
local _activeTab = "weapon"

-- crosshair (celownik) + pulsujacy obrys
local _cursorGui, _reticle, _cursorTint = nil, nil, {}

-- clear-plot 2-krok
local _clearBtn, _clearLbl, _clearArmed, _clearToken = nil, nil, false, 0
local _clearOrigText = "Clear plot!" -- oryginalny napis przycisku (przywracany po confirm)

-- czy gracz cos aktualnie stawia (ghost aktywny) — UnitTooltip pyta, by nie pokazywac dymka swiata podczas stawiania
function BuildController.HasSelection()
	return _sel ~= nil
end

-- czy TRYB BUDOWANIA jest otwarty (panel aktywny). UnitTooltip pyta: dymek swiata TYLKO w trybie wolnym.
function BuildController.IsBuildMode()
	return _on
end

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
-- dt-znormalizowany wspolczynnik lerpa: LERP = tempo przy referencyjnych 60fps (exponential smoothing),
-- niezalezne od FPS — przy niskich klatkach ghost dogania w tym samym TEMPIE co przy wysokich.
local function ghostAlpha(dt)
	return 1 - (1 - LERP) ^ (math.max(dt or 0, 0) * 60)
end

-- lerp kata (w stopniach) NAJKROTSZA droga — np. 350->10 idzie przez 0, nie przez 180.
local function lerpAngleDeg(cur, target, alpha)
	local diff = ((target - cur + 180) % 360) - 180
	return cur + diff * alpha
end

local function orientAt(pos, groundY, yawDeg)
	return CFrame.lookAlong(Vector3.new(pos.X, groundY, pos.Z), _plot.faceDir) * CFrame.Angles(0, math.rad(yawDeg), 0)
end

local function clearGhost()
	if _ghost then _ghost:Destroy(); _ghost = nil end
	if _ring then _ring:Destroy(); _ring = nil end
	_ghostPos = nil
	_ghostSurfaceY = nil
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
		if factor < 0.999 and g.ScaleTo then g:ScaleTo(g:GetScale() * factor) end
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
	_ghostSurfaceY = nil -- jw. dla wysokosci (nie "spada" z poprzedniej wysokosci stosu)
	-- UWAGA: _ghostYaw CELOWO nie resetujemy — _rot persystuje miedzy postawieniami (patrz stan wyzej),
	-- wiec obrot ghosta ma plynnie dojechac do _rot zamiast skakac przy kazdym makeGhost() (np. klawisz R).
end

-- czy wskaznik/palec jest GEOMETRYCZNIE nad kontrolkami mobilnymi (co klatke, bez timingu/gp)?
-- To gwarantuje: klik po GUI NIE rusza ghosta ("sztywno", input nie przebija guzika w swiat).
local function guiAtHitsControls(x, y)
	local ok, objs = pcall(function() return LP.PlayerGui:GetGuiObjectsAtPosition(x, y) end)
	if not ok or not objs then return false end
	for _, o in ipairs(objs) do
		if o == _mobileControls or o:IsDescendantOf(_mobileControls) then return true end
	end
	return false
end
local function pointerOverControls()
	if not _mobileControls or not _mobileControls.Visible then return false end
	local mp = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	-- GetMouseLocation jest z insetem, GetGuiObjectsAtPosition liczy w AbsolutePosition (bez insetu) —
	-- sprawdzamy OBIE przestrzenie, zeby test byl odporny na inset (BuildMode ma IgnoreGuiInset=true).
	return guiAtHitsControls(mp.X - inset.X, mp.Y - inset.Y) or guiAtHitsControls(mp.X, mp.Y)
end

local function updateGhost(dt)
	if not _ghost or not _plot then return end
	local c = cursorCell()
	if c and not _suppressGhost and not pointerOverControls() then _cell = c end -- ray trafil w plaszczyzne -> zaktualizuj (clamped). Miss/palec-na-przyciskach -> zostaw ostatnia kratke.
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
	local alpha = ghostAlpha(dt)
	_ghostPos = _ghostPos and _ghostPos:Lerp(targetPos, alpha) or targetPos
	_ghostYaw = _ghostYaw and lerpAngleDeg(_ghostYaw, _rot, alpha) or _rot
	_ghostSurfaceY = _ghostSurfaceY and (_ghostSurfaceY + (surfaceY - _ghostSurfaceY) * alpha) or surfaceY
	-- WSZYSTKIE TRZY osie plynne i dt-znormalizowane: pozycja XZ, obrot, wysokosc (siadanie na stosie)
	_ghost:PivotTo(orientAt(_ghostPos, groundY, _ghostYaw))
	local bbCf, bbSize = _ghost:GetBoundingBox()
	_ghost:PivotTo(_ghost:GetPivot() + Vector3.new(0, _ghostSurfaceY - (bbCf.Position.Y - bbSize.Y * 0.5), 0))
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
		_ring.CFrame = CFrame.new(_ghostPos.X, _ghostSurfaceY + 0.3, _ghostPos.Z) * CFrame.Angles(0, 0, math.rad(90))
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

-- pokaz podpowiedzi/przyciski wg platformy: PC -> PcControls, telefon -> MobileControls (dotykowe)
local function setPcControls(vis)
	if _pcControls then _pcControls.Visible = vis and not IS_MOBILE end
	if _mobileControls then _mobileControls.Visible = vis and IS_MOBILE end
end

-- ── feedback: scale-pop przy postawieniu, scale-down+dzwiek przy usunieciu ──
-- Model.Scale (property) jest tylko-do-odczytu-ze-skryptu (Studio-only, dokumentacja Roblox) — jedyny sposob
-- animowania skali z LocalScript to tweenowanie posredniego NumberValue i wolanie Model:ScaleTo() na kazdej zmianie.
local function tweenModelScale(model, fromScale, toScale, duration, style, dir)
	if not model or not model.Parent then return end
	if not pcall(function() model:ScaleTo(fromScale) end) then return end
	local proxy = Instance.new("NumberValue")
	proxy.Value = fromScale
	local conn
	conn = proxy.Changed:Connect(function(v)
		if model.Parent then pcall(function() model:ScaleTo(v) end) end
	end)
	local tw = TweenService:Create(proxy, TweenInfo.new(duration, style or Enum.EasingStyle.Back, dir or Enum.EasingDirection.Out), { Value = toScale })
	tw.Completed:Connect(function()
		conn:Disconnect()
		proxy:Destroy()
	end)
	tw:Play()
end

local function playPopSound(parent, pitch)
	local snd = Instance.new("Sound")
	snd.SoundId = POP_SOUND_ID
	snd.Volume = 0.45
	snd.PlaybackSpeed = pitch or 1
	snd.Parent = parent
	snd:Play()
	Debris:AddItem(snd, 2)
end

-- scale-pop 0.9->1.0 na swiezo postawionym/przesunietym modelu (serwer juz potwierdzil, res.ok)
local function popPlaced(model)
	if not model then return end
	tweenModelScale(model, 0.9, 1.0, 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	playPopSound(model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") or model, 1)
end

-- szybki scale-down + dzwiek TUZ PRZED wyslaniem RemoveUnit — serwer niszczy model natychmiast (bez animacji),
-- wiec cala animacja usuwania musi zdazyc zagrac lokalnie zanim replikacja Destroy() dogoni model.
local function playRemoveFx(model)
	if not model then return end
	local okScale, curScale = pcall(function() return model:GetScale() end)
	tweenModelScale(model, okScale and curScale or 1, 0.05, 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	playPopSound(model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") or model, 0.75)
end

-- poll (kilka klatek) po WR_Units — replikacja spawnu modelu z serwera nie jest natychmiastowa
local function findModelByPlacementId(id, maxTries)
	for _ = 1, (maxTries or 10) do
		local units = Workspace:FindFirstChild("WR_Units")
		if units then
			for _, m in ipairs(units:GetChildren()) do
				if m:GetAttribute("PlacementId") == id then return m end
			end
		end
		task.wait()
	end
	return nil
end

-- j.w., ale dla MoveUnit — serwer nie zwraca nowego placementId, wiec szukamy po wlasciciel+kratka docelowa
local function findModelAtCell(x, z, maxTries)
	for _ = 1, (maxTries or 10) do
		local units = Workspace:FindFirstChild("WR_Units")
		if units then
			for _, m in ipairs(units:GetChildren()) do
				if m:GetAttribute("OwnerUserId") == LP.UserId and m:GetAttribute("CellX") == x and m:GetAttribute("CellZ") == z then
					return m
				end
			end
		end
		task.wait()
	end
	return nil
end

-- #9: plansza pelna? (ta sama kalkulacja co validAt: zajete + footprint wybranej > budzet).
-- occupancy(_moving) pomija przenoszona jednostke -> przenoszenie po pelnej planszy NIE jest "pelne".
local function budgetFull()
	if not _sel then return false end
	local _, used = occupancy(_moving)
	return used + _sel.fp.w * _sel.fp.d > _budget
end

-- #9: "board full" — feedback zamiast cichego nic gdy GridService odrzuca (BudgetExceeded).
-- Idzie teraz przez DESIGNEROWY Notify (Notifications.Template); dedup klik-spamu w samym Notify.
local function showBudgetToast()
	Notify.show("Board full, no free slots!")
end

-- ── akcje ──
local function place()
	if not _sel or not _cell then return end
	if not validAt(_cell.x, _cell.z) then
		if budgetFull() then showBudgetToast() end -- #9: pelna plansza -> powiedz graczowi (inne blokady = cicho)
		return
	end
	if _moving then
		-- przenoszenie juz postawionej jednostki (bez zwrotu do inventory)
		local destX, destZ = _cell.x, _cell.z
		local res = Net.get("MoveUnit"):InvokeServer(_moving, _cell.x, _cell.z, _rot)
		if res and res.ok then
			_moving = nil; _movingModel = nil -- serwer zniszczyl stary i postawil nowy model
			_sel = nil
			clearGhost()
			setPcControls(false); setCursor(false)
			BuildController._refreshCounter()
			task.spawn(function() popPlaced(findModelAtCell(destX, destZ, 10)) end)
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
		if res.placementId then
			task.spawn(function() popPlaced(findModelByPlacementId(res.placementId, 10)) end)
		end
	elseif res and res.reason == "BudgetExceeded" then
		showBudgetToast() -- #9: serwer odrzucil za budzet (klient/serwer rozjazd) -> toast
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

local function updateHover(color)
	local m = unitUnderCursor()
	if m == _hovered then return end
	clearHover()
	if m then
		local hl = Instance.new("Highlight")
		hl.Name = "WR_HoverHL"
		hl.Adornee = m
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.OutlineColor = color or WHITE
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
		playRemoveFx(m)
		Net.get("RemoveUnit"):InvokeServer(m:GetAttribute("PlacementId"))
		BuildController._refreshCounter()
	end
end

-- Napis przycisku ma WARSTWY (kit: ClearPlot.TextLabel + zagniezdzony .TextLabel dla obrysu). Zmiana
-- tylko najglebszej zostawiala "Clear Plot!" na warstwie zewnetrznej za "Are you sure?". Ustaw WSZYSTKIE.
local function setClearText(txt)
	if not _clearBtn then return end
	for _, d in ipairs(_clearBtn:GetDescendants()) do
		if d:IsA("TextLabel") then d.Text = txt end
	end
end

-- Wyczysc dzialke: 1. klik uzbraja ("Czy jestes pewny?"), 2. klik czysci naraz (ClearPlot).
local function clearPlot()
	if not _clearArmed then
		_clearArmed = true
		setClearText("Are you sure?")
		_clearToken += 1
		local tok = _clearToken
		task.delay(3, function() -- auto-rozbrojenie po 3 s
			if _clearArmed and _clearToken == tok then
				_clearArmed = false
				setClearText(_clearOrigText)
			end
		end)
		return
	end
	_clearArmed = false
	_clearToken += 1
	setClearText(_clearOrigText)
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
				-- Stats = nakladka na karte (ziomek: Frame 1x1, domyslnie Visible=false) pokazywana PRZY NAJECHANIU.
				-- Bron/pulapka: ⚔️ DMG/s + ❤️ HP. Blok: tylko ❤️ HP (wiersz Attack ukryty).
				local stats = card:FindFirstChild("Stats")
				local atkFrame = stats and stats:FindFirstChild("Attack")
				local atkL = atkFrame and atkFrame:FindFirstChild("TextLabel")
				local hpL = stats and stats:FindFirstChild("Health") and stats.Health:FindFirstChild("TextLabel")
				local dps = u.combat and (u.combat.dmg or 0) * (u.combat.fireRate or 1) or 0
				if atkFrame then atkFrame.Visible = u.combat ~= nil end
				if atkL then atkL.Text = "⚔️ " .. fmtNum(dps) .. "/s" end
				if hpL then hpL.Text = "❤️ " .. fmtNum(u.hp or 0) end
				if stats then stats.Visible = false end
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
				-- najechanie -> pokaz nakladke ze statystykami NA karcie (jak w grze-wzorze), zejscie -> schowaj
				if stats then
					card.MouseEnter:Connect(function() stats.Visible = true end)
					card.MouseLeave:Connect(function() stats.Visible = false end)
				end
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
	local layout
	for _, c in ipairs(_list:GetChildren()) do
		if c:IsA("UIListLayout") then layout = c break end
	end
	if not layout then return end
	local W = _list.AbsoluteSize.X
	local H = _content.AbsoluteSize.Y
	if W < 1 or H < 1 then return end
	local pad = layout.Padding.Offset
	-- 3 KOLUMNY (szerokosc karty = 0.30*listW) + wypelnij wysokosc CALYMI rzedami: dobierz liczbe rzedow N
	-- najblizej kwadratu i ustaw aspect karty tak, by N rzedow zajelo cala wysokosc -> BRAK partial-rzedu na dole
	-- (zadne "x8" nie wystaje poza ramke) i BRAK pustego miejsca. Nadmiar (>N rzedow) = scroll kolkiem.
	local cardW = 0.30 * W
	local N = math.max(1, math.floor(H / cardW + 0.5))
	local cardH = (H - (N - 1) * pad) / N
	local A = cardW / math.max(cardH, 1)
	for _, c in ipairs(_list:GetChildren()) do
		if c:IsA("GuiButton") then
			local arc = c:FindFirstChildOfClass("UIAspectRatioConstraint")
			if arc then arc.AspectRatio = A; arc.DominantAxis = Enum.DominantAxis.Width end
			c.Size = UDim2.new(0.30, 0, 1, 0)
		end
	end
	_list.Size = UDim2.new(_list.Size.X.Scale, _list.Size.X.Offset, 1, 0)
end

local function setTab(t)
	_activeTab = t
	for id, b in pairs(_tabBtns) do
		if b then
			local st = b:FindFirstChildOfClass("UIStroke")
			if st then st.Enabled = true end -- obrys ZAWSZE widoczny (user); zaznaczenie = BackgroundTransparency nizej
			b.BackgroundTransparency = (id == t) and 0 or 0.4
		end
	end
	BuildController._refreshPanel()
end

local function setHudHidden(hidden)
	if hidden then HudOverlay.enter(false) else HudOverlay.exit() end
end

-- user: w trybie budowania chowamy koniczyne (Luck) i kostke (None) z prawego-dolnego rogu HUD
-- (SideButtons.BottomRightCanvas). Zapamietujemy oryginalna widocznosc i przywracamy przy wyjsciu.
local function hideLuckDice()
	_brSaved = {}
	local pg = LP:FindFirstChild("PlayerGui")
	local sb = pg and pg:FindFirstChild("SideButtons")
	local brc = sb and sb:FindFirstChild("BottomRightCanvas")
	if not brc then return end
	for _, n in ipairs({ "Luck", "None" }) do
		local o = brc:FindFirstChild(n)
		if o and o:IsA("GuiObject") then
			_brSaved[#_brSaved + 1] = { o, o.Visible }
			o.Visible = false
		end
	end
end
local function restoreLuckDice()
	for _, rec in ipairs(_brSaved) do
		if rec[1] and rec[1].Parent then rec[1].Visible = rec[2] end
	end
	_brSaved = {}
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
	hideLuckDice() -- user: schowaj koniczyne+kostke z prawego-dolnego rogu w budowaniu
	setTab(_activeTab)
	BuildController._refreshCounter()
end

local function closeBuild()
	_on = false
	cancelSelection()
	_mode = "place"
	if _bm then _bm.Enabled = false end
	setHudHidden(false)
	restoreLuckDice() -- przywroc koniczyne+kostke po wyjsciu z budowania
	UserInputService.MouseIconEnabled = true
end

function BuildController.start()
	makeCursor()

	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_Build"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 30
	gui.Parent = LP:WaitForChild("PlayerGui")

	-- "board full" idzie teraz przez designerowy Notify (Notifications.Template) — patrz showBudgetToast().

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
		-- UWAGA: przycisk taba jednostek w designerowym UI nazywa sie "Units" (nie "Weapons") -> szukamy obu,
		-- inaczej weapon = nil -> klik w tab jednostek niepodpiety -> nie da sie wrocic z Blocks na jednostki.
		_tabBtns = { block = btns and btns:FindFirstChild("Blocks"), weapon = btns and (btns:FindFirstChild("Units") or btns:FindFirstChild("Weapons")) }
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
		-- DOTYKOWE przyciski (Accept/Rotate/Cancel) przeniesione z _dev do BuildMode.MobileControls.
		-- Ta sama akcja co PC: Accept=postaw, Rotate=obrot, Cancel=anuluj. Pokazywane tylko na telefonie.
		_mobileControls = buildMode:FindFirstChild("MobileControls")
		if _mobileControls then
			local function wireMobile(childName, fn)
				local f = _mobileControls:FindFirstChild(childName)
				local btn = f and (f:FindFirstChild("Button") or (f:IsA("GuiButton") and f)) or nil
				if btn and btn:IsA("GuiButton") then
					btn.MouseButton1Click:Connect(fn)
					-- palec DOTYKA przycisku -> zamroz ghosta (inaczej dotyk przenosi jednostke pod przycisk)
					btn.MouseButton1Down:Connect(function() _suppressGhost = true end)
				end
			end
			wireMobile("Accept", function() if _sel and _cell then place() end end) -- #9: place() waliduje + toast
			wireMobile("Rotate", function() if _sel then _rot = (_rot + 90) % 360; makeGhost() end end)
			wireMobile("Cancel", function() if _sel then cancelSelection() end end)
			-- odmroz ghosta po puszczeniu palca (globalnie, na wypadek zjechania palcem poza przycisk)
			UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
					_suppressGhost = false
				end
			end)
		end
		setPcControls(false)
		buildMode.Enabled = false
	else
		warn("[BuildController] brak StarterGui.BuildMode")
	end

	local function doToggle()
		if _on then closeBuild() else openBuild() end
	end
	BuildController.Toggle = doToggle -- HUD ziomka (SideButtons.Build) wola to

	-- input: LPM stawia/podnosi/usuwa, R obraca, X anuluje. PPM CELOWO nic nie robi z trzymana
	-- jednostka (user: PPM podczas trzymania ghosta NIE ma go usuwac) -> zostaje kamerze. Anulowanie = X / mobilny Cancel.
	UserInputService.InputBegan:Connect(function(input, gp)
		if not _on then return end
		-- DOTYK/KLIK w GUI (przyciski Accept/Rotate/Cancel, panele) -> zamroz ghosta, zeby nie skoczyl pod palec.
		-- gameProcessedEvent jest niezawodne dla dotyku (inaczej niz MouseButton1Down na GuiButton).
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			_suppressGhost = gp
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if gp then return end -- klik w UI panelu (karty) — nie stawiaj
			if _mode == "delete" then
				deleteAt()
			elseif _sel then
				if _cell then place() end -- #9: place() sam waliduje + toast gdy budzet pelny
			end
			-- user: LMB na postawiona jednostke NIE podnosi/usuwa jej (dawny pickup-do-przeniesienia wygladal
			-- jak usuniecie: oryginal znikal). USUWANIE jednostek TYLKO w trybie Delete (przycisk Delete).
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
			updateGhost(dt)
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
				-- MOBILE: przyciski Accept/Rotate/Cancel NAD itemem (ghostem), sledza go; poza wyborem itemu ukryte.
				if IS_MOBILE and _mobileControls then _mobileControls.Position = UDim2.fromOffset(sp.X + inset.X, sp.Y + inset.Y - 8) end
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
			if _mode == "place" then updateHover(WHITE) elseif _mode == "delete" then updateHover(RED) else clearHover() end
			if _cursorGui.Enabled then setCursor(false) end
		end
	end)
end

return BuildController
