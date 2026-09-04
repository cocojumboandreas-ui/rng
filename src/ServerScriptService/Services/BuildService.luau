--!nonstrict
-- ServerScriptService/Services/BuildService.luau  (§3.7)
-- Orkiestracja stawiania/usuwania: spina Inventory + Grid + Workspace + faze. Jedyny wlasciciel modeli na plocie.
-- KONTRAKT (decyzja Olo): Net.PlaceUnit(itemId, cellX, cellZ) gdzie itemId = invKey "unitId#mutationId"
--   (dokladnie to co zwraca Inventory.GetCounts). Split na PIERWSZYM "#"; pusty mutationId -> mut=nil.
--   Placement zapisuje {itemId=unitId, x, z, mut=mutationId|nil}.
-- WALIDACJA SERWEROWA (nie ufamy klientowi): faza Building -> legalny unitId (UnitsConfig)
--   -> gracz posiada >=1 DOKLADNEGO wariantu -> Grid.CanPlace -> Occupy -> Inventory.Consume.
-- Zero rotation w danych: orientacja liczona przy stawianiu z PlotInfo.faceDirection.
-- deps: InventoryService, GridService, PlotService, WaveService (faza), ProfileService.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local GridMath = require(Framework:WaitForChild("GridMath"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared:WaitForChild("Enums"))
local UnitModelFactory = require(Shared:WaitForChild("UnitModelFactory"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local BuildService = {}

local _inv, _grid, _plot, _wave, _profile = nil, nil, nil, nil, nil
local _models: { [any]: { [string]: Instance } } = {} -- player -> {placementId -> Model}
local _snapshot: { [any]: any } = {} -- player -> {pid -> placementCopy} — stan bazy na START fali (restore po fali)
local _restoredOnLeave: { [any]: boolean } = {} -- player -> guard: RestoreBase@ProfileReleasing max RAZ na wyjscie
local _unitsFolder: Folder? = nil

-- ── helpers czyste ───────────────────────────────────────────────────────────
-- split invKey "unitId#mutationId#variant" -> unitId, mutId(nil gdy pusty), variant(regular gdy brak).
-- Toleruje stary 2-czesciowy klucz "unitId#mut" (variant -> regular) — segmenty bez "#".
local function parseItemId(itemId: string)
	local parts = string.split(itemId, "#")
	local unitId = parts[1] or itemId
	local mutId = parts[2]
	if mutId == "" then
		mutId = nil
	end
	local variant = parts[3]
	if variant == nil or variant == "" then
		variant = "regular"
	end
	return unitId, mutId, variant
end

local function mutObject(mutId: string?)
	if not mutId then
		return nil
	end
	for _, m in ipairs(GameConfig.Mutation.ladder) do
		if m.id == mutId then
			return { id = m.id, mult = m.mult }
		end
	end
	return { id = mutId } -- nieznana mutacja: ownership-check i tak odrzuci
end

-- ── stan (orkiestracja, bez Workspace) ───────────────────────────────────────
-- (ok, placementId | reason). reason: NotBuilding|UnknownUnit|NotOwned|OutOfBounds|Occupied|BudgetExceeded
local function doPlace(player, itemId: string, cellX: number, cellZ: number, rot: number?)
	if _wave.GetPhase(player) ~= Enums.RunPhase.Building then
		return false, "NotBuilding"
	end
	local unitId, mutId, variant = parseItemId(itemId)
	if GameConfig.Units[unitId] == nil then
		return false, "UnknownUnit"
	end
	local mutation = mutObject(mutId)
	-- ownership: gracz musi miec >=1 DOKLADNEGO wariantu (kanoniczny invKey z 3 osi)
	local canonicalKey = _inv.KeyFor(unitId, mutation, variant)
	local counts = _inv.GetCounts(player)
	if (counts[canonicalKey] or 0) < 1 then
		return false, "NotOwned"
	end
	local canOK, reason = _grid.CanPlace(player, unitId, cellX, cellZ)
	if not canOK then
		return false, reason
	end
	local pid = HttpService:GenerateGUID(false)
	local layer = _grid.Occupy(player, pid, unitId, cellX, cellZ) -- zwraca warstwe stosu
	if not _inv.Consume(player, unitId, mutation, variant) then
		_grid.Free(player, pid) -- rollback (nie powinno sie zdarzyc po ownership-check)
		return false, "NotOwned"
	end
	local data = _profile.GetProfile(player)
	if data then
		data.placements[pid] = { itemId = unitId, x = cellX, z = cellZ, mut = mutId, variant = variant, rot = rot or 0, layer = layer }
	end
	return true, pid
end

-- (ok, reason). Przenosi juz postawiona jednostke na nowa kratke (bez ruszania inventory).
-- WALIDACJA: zwalniamy stare kratki, sprawdzamy nowe (wiec kolizja z samym soba nie blokuje), przy porazce rollback.
-- reason: NotBuilding|NoSuchPlacement|OutOfBounds|Occupied|BudgetExceeded|UnknownUnit
local function doMove(player, placementId: string, cellX: number, cellZ: number, rot: number?)
	if _wave.GetPhase(player) ~= Enums.RunPhase.Building then
		return false, "NotBuilding"
	end
	local data = _profile.GetProfile(player)
	local p = data and data.placements[placementId]
	if not p then
		return false, "NoSuchPlacement"
	end
	-- EDYCJA dowolnej warstwy: przenosimy nawet dolny blok; to co bylo na nim zostaje "w powietrzu".
	local unitId = p.itemId
	local oldX, oldZ, oldLayer = p.x, p.z, p.layer
	_grid.Free(player, placementId)
	local canOK, reason = _grid.CanPlace(player, unitId, cellX, cellZ)
	if not canOK then
		_grid.Occupy(player, placementId, unitId, oldX, oldZ, oldLayer) -- rollback na starą warstwe
		return false, reason
	end
	local layer = _grid.Occupy(player, placementId, unitId, cellX, cellZ)
	p.x, p.z, p.rot, p.layer = cellX, cellZ, rot or 0, layer
	return true
end

-- (ok, reason). reason: NotBuilding|NoSuchPlacement
local function doRemove(player, placementId: string)
	if _wave.GetPhase(player) ~= Enums.RunPhase.Building then
		return false, "NotBuilding"
	end
	local data = _profile.GetProfile(player)
	local p = data and data.placements[placementId]
	if not p then
		return false, "NoSuchPlacement"
	end
	-- EDYCJA dowolnej warstwy: usuwamy nawet dolny blok; to co bylo na nim zostaje "w powietrzu".
	_grid.Free(player, placementId)
	_inv.Refund(player, p.itemId, mutObject(p.mut), p.variant or "regular")
	data.placements[placementId] = nil
	return true
end

-- ── Workspace (runtime) ──────────────────────────────────────────────────────
local function ensureUnitsFolder(): Folder
	if _unitsFolder and _unitsFolder.Parent then
		return _unitsFolder
	end
	local f = Workspace:FindFirstChild("WR_Units")
	if not f then
		f = Instance.new("Folder")
		f.Name = "WR_Units"
		f.Parent = Workspace
	end
	_unitsFolder = f
	return f
end

local FIT_MARGIN = 0.8 -- odstep od krawedzi kratki (mniejszy = jednostka ciasniej wpasowana w obrys)
local LAYER_H = GameConfig.Grid.cellSize -- wysokosc jednej warstwy stosu (bloki = kostki tej wysokosci)

-- Skalowanie modelu przez BEZPOSREDNI BasePart.Size (nie Model:ScaleTo): ScaleTo z serwera NIE replikuje
-- sie do klienta dla pojazdow-meshy (jednostka olbrzymia u gracza), a bezposrednia zmiana Size TAK.
-- Efekt geometryczny identyczny jak ScaleTo (zweryfikowane: ext diff 0.0000).
local function scaleModelDirect(model, f)
	if f == 1 then return end
	local pivot = model:GetPivot().Position
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Size = d.Size * f
			d.Position = pivot + (d.Position - pivot) * f
		elseif d:IsA("DataModelMesh") then
			d.Scale = d.Scale * f
		elseif d:IsA("Attachment") then
			d.Position = d.Position * f
		end
	end
end

-- Model.Scale != 1 (upieczone ScaleTo w szablonie, np. czolg 0.633, bron ciezka 2.213) NIE replikuje sie
-- serwer->klient -> na kliencie jednostka renderuje sie w NATYWNYM rozmiarze (za duza, wtapia sie gasienica).
-- Upieka biezacy WYGLAD w Size/CFrame przy Scale=1, zeby dalsze skalowanie szlo z bazy Scale=1 (replikuje sie).
local function normalizeModelScale(model)
	if not model.GetScale or math.abs(model:GetScale() - 1) < 1e-3 then return end
	local pivot = model:GetPivot()
	local snap = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then snap[#snap + 1] = { d, "p", d.Size, pivot:ToObjectSpace(d.CFrame) }
		elseif d:IsA("DataModelMesh") then snap[#snap + 1] = { d, "m", d.Scale }
		elseif d:IsA("Attachment") then snap[#snap + 1] = { d, "a", d.Position } end
	end
	model:ScaleTo(1)
	for _, e in ipairs(snap) do
		if e[2] == "p" then e[1].Size = e[3]; e[1].CFrame = pivot * e[4]
		elseif e[2] == "m" then e[1].Scale = e[3]
		elseif e[2] == "a" then e[1].Position = e[3] end
	end
end

local function spawnModel(player, unitId: string, placementId: string, cellX: number, cellZ: number, rot: number?)
	local plot = _plot.GetPlot(player)
	if not plot then
		warn("[BuildService] spawnModel: brak plotu gracza")
		return nil
	end
	-- Model przez UnitModelFactory: prawdziwy z Assets.Units albo placeholder z kodu (blok/bron).
	local template = UnitModelFactory.get(unitId)
	if not template then
		warn(("[BuildService] UnitModelFactory nie zwrocil modelu dla '%s'"):format(tostring(unitId)))
		return nil
	end
	local ucfg = GameConfig.Units[unitId]
	local fp = ucfg.footprint
	local isBlock = ucfg.combat == nil -- blok/pulapka (bez combat) — pojedynczy Part robimy kostka do stackowania
	local layer = (_grid and _grid.GetLayer(player, placementId)) or 0 -- warstwa stosu (0 = ziemia)
	local model = template:Clone()

	-- PrimaryPart: modele ze store czesto go nie maja -> ustaw (HumanoidRootPart albo najwieksza czesc).
	-- WAZNE (#modele): rigi R6 sa ZAGNIEZDZONE w sub-modelu "Dummy" -> HRP szukamy REKURSYWNIE. Inaczej
	-- fallback na "najwieksza czesc" bral np. minigun tank_soldiera ("MainPart" authored +X) jako pivot i
	-- CALA jednostka orientowala sie bokiem (soldier/swat dzialaly przypadkiem — ich najwieksza czesc=Vest
	-- jest wyrownana z rigiem). PrimaryPart=HRP => orientacja liczona po rdzeniu riga, cialo patrzy w faceDir.
	if not model.PrimaryPart then
		local hrp = model:FindFirstChild("HumanoidRootPart", true)
		if hrp and hrp:IsA("BasePart") then
			model.PrimaryPart = hrp
		else
			local biggest, bestVol = nil, -1
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					local v = d.Size.X * d.Size.Y * d.Size.Z
					if v > bestVol then bestVol, biggest = v, d end
				end
			end
			model.PrimaryPart = biggest
		end
	end

	-- POJAZD/mesh: upiecz Model.Scale do 1 (Scale != 1 nie replikuje sie na klienta). R6 rigi pomijamy (Motor6D).
	if not model:FindFirstChildOfClass("Humanoid") then
		normalizeModelScale(model)
	end

	-- ORIENTACJA NAJPIERW (front = faceDirection), potem pomiar/skala — GetExtentsSize jest
	-- osiowany w swiecie, wiec mierzenie przed obrotem dawalo zle osie (np. dlugi czolg nie miescil Z).
	local center = GridMath.cellToWorld(plot.gridOrigin, GameConfig.Grid.cellSize, cellX, cellZ, fp).Position
	local groundY = plot.gridOrigin.Position.Y
	-- baza = zwrot na wroga (faceDirection); rot = RECZNY obrot gracza (yaw) doklejony na wierzch (kosmetyka renderu)
	model:PivotTo(
		CFrame.lookAlong(Vector3.new(center.X, groundY, center.Z), plot.faceDirection)
			* CFrame.Angles(0, math.rad(rot or 0), 0)
	)

	-- Fit-to-cell / BLOK: pojedynczy Part bloku -> KOSTKA wypelniajaca kratke o STALEJ wysokosci LAYER_H
	-- (czyste stackowanie: jednostka na 4 blokach siada rowno). Inne modele: skala do footprintu (margines).
	local cellW = fp.w * GameConfig.Grid.cellSize
	local cellD = fp.d * GameConfig.Grid.cellSize
	local blockParts = {}
	if isBlock then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then blockParts[#blockParts + 1] = d end
		end
	end
	if isBlock and #blockParts == 1 then
		blockParts[1].Size = Vector3.new(cellW * 0.95, LAYER_H, cellD * 0.95)
	else
		local size = model:GetExtentsSize() -- juz w orientacji docelowej
		local factor = math.min(cellW / math.max(size.X, 0.01), cellD / math.max(size.Z, 0.01)) * FIT_MARGIN
		factor = math.min(factor, 1)
		if model:FindFirstChildOfClass("Humanoid") then
			-- R6 rig: Model:ScaleTo (skaluje tez Motor6D dla animacji klienta), dziala lokalnie.
			-- ScaleTo jest ABSOLUTNE, a factor to stosunek do OBECNEGO rozmiaru -> * GetScale() (upieczona skala).
			if factor < 0.999 and model.ScaleTo then
				model:ScaleTo(model:GetScale() * factor)
			end
			if model.GetScale and model.ScaleTo then
				local s2 = model:GetExtentsSize()
				local over = math.max(s2.X / cellW, s2.Z / cellD)
				if over > 1 then model:ScaleTo(model:GetScale() / over * 0.98) end
			end
		else
			-- POJAZD/mesh: skaluj przez BEZPOSREDNI Size (Model:ScaleTo z serwera NIE replikuje sie do
			-- klienta dla tych modeli -> jednostka olbrzymia u gracza; bezposredni Size replikuje sie).
			if factor < 0.999 then scaleModelDirect(model, factor) end
			local s2 = model:GetExtentsSize()
			local over = math.max(s2.X / cellW, s2.Z / cellD)
			if over > 1 then scaleModelDirect(model, 1 / over * 0.98) end
		end
	end

	-- PODSTAWA na WIERZCHU stosu: ziemia + layer * wysokosc warstwy (layer 0 = na kaflach)
	local surfaceY = groundY + layer * LAYER_H + 0.3 -- +clearance: jednostka siada NAD powierzchnia (koniec z-fightingu/wtapiania gasienic)
	local bbCf, bbSize = model:GetBoundingBox()
	local lift = surfaceY - (bbCf.Position.Y - bbSize.Y * 0.5)
	model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))

	-- RECENTER XZ: STOPY (HumanoidRootPart) w SRODEK kratki — nie pistolet/bbox (dla blokow/pojazdow: srodek bbox).
	-- Musi zgadzac sie z ghostem po stronie klienta (BuildController.updateGhost).
	local anchor = model:FindFirstChild("HumanoidRootPart", true)
	local aPos = (anchor and anchor:IsA("BasePart")) and anchor.Position or (select(1, model:GetBoundingBox())).Position
	model:PivotTo(model:GetPivot() + Vector3.new(center.X - aPos.X, 0, center.Z - aPos.Z))

	-- KIEROWCA (np. Jeep): dokomponuj model kierowcy w fotel przod-lewo (kompozycja przed kotwiczeniem)
	if ucfg.driver then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local uf = assets and assets:FindFirstChild("Units")
		local dtmpl = uf and uf:FindFirstChild(ucfg.driver)
		if dtmpl then
			local driver = dtmpl:Clone()
			if not driver.PrimaryPart then
				driver.PrimaryPart = driver:FindFirstChild("HumanoidRootPart")
			end
			local _, vSize = model:GetBoundingBox()
			local dScale = (vSize.Y * 0.8) / math.max(driver:GetExtentsSize().Y, 0.01)
			scaleModelDirect(driver, dScale) -- bezposredni Size (ScaleTo z serwera nie replikuje sie do klienta)
			local pivot = model:GetPivot()
			local seat = pivot * CFrame.new(-vSize.X * 0.22, 0, -vSize.Z * 0.1)
			driver:PivotTo(CFrame.lookAlong(seat.Position, pivot.LookVector))
			local dh = driver:FindFirstChildOfClass("Humanoid")
			if dh then dh.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end -- ukryj nametag "Dummy"
			driver.Name = "WR_Driver"
			driver.Parent = model
		end
	end

	-- Statyczny render: zakotwicz WSZYSTKIE czesci (zero fizyki/ragdoll), animacja = kosmetyka klienta.
	-- CanQuery = true: KLUCZOWE dla trybu budowania — klient raycastuje jednostki (hover/pickup/delete).
	-- CanCollide = true: jednostki sa NIEPRZECHODNE — gracz nie przechodzi przez nie, moze na nie wskoczyc.
	--   Wrogowie chodza po pathT (CFrame, bez fizyki), wiec kolizja jednostek ich nie blokuje.
	-- R6 humanoid: realne animacje (Animator) -> kotwicz TYLKO HRP + spaw dodatkow (RigAnimSetup).
	-- Reszta (pojazdy, wieze, bloki): zakotwicz wszystko jak dotychczas.
	-- POJAZD z kierowca (ucfg.driver): NIE odpalaj prepare — inaczej wykryje Humanoida kierowcy,
	-- przyspawa nadwozie do kierowcy i odkotwiczy je -> jeep rozlatuje sie w fizyce. Wtedy kotwiczymy wszystko.
	local isR6 = (not ucfg.driver) and (require(ReplicatedStorage.Framework.RigAnimSetup).prepare(model) ~= nil)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if not isR6 then
				d.Anchored = true
			end
			d.CanCollide = true
			d.CanQuery = true
		end
	end

	-- #modele: minigun heavy (tank_soldier) — RigAnimSetup WELDUJE obracana lufe do riga (Torsa), a klient
	-- (UnitCombatAnimator) wymusza jej CFrame co klatke (spin) -> konflikt weld<->CFrame SZARPIE calym rigiem
	-- ("obracal sie caly" przy strzale). Odczep lufe (usun RigAnimWeld) + zakotwicz NA SERWERZE (klient-side
	-- sie nie utrzymuje, czesc jest server-owned) -> spin izolowany, cialo stoi idle. Tylko czesci "barrel"/
	-- "minigun" (ma je jedynie minigun) -> pozostale rigi (soldier/swat) nietkniete.
	if isR6 then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name:lower():find("barrel") or d.Name:lower():find("minigun")) then
				for _, w in ipairs(d:GetChildren()) do
					if w:IsA("WeldConstraint") or w:IsA("Weld") then w:Destroy() end
				end
				d.Anchored = true
			end
		end
	end

	model:SetAttribute("PlacementId", placementId)
	model:SetAttribute("OwnerUserId", typeof(player) == "Instance" and player.UserId or 0)
	model:SetAttribute("UnitId", unitId) -- klient (UnitAnimator) rozpoznaje typ jednostki
	model:SetAttribute("CellX", cellX) -- tryb budowania: klient liczy zajetosc kratek wlasnego plotu
	model:SetAttribute("CellZ", cellZ)
	model:SetAttribute("Rot", rot or 0) -- reczny obrot (klient odczytuje przy podniesieniu jednostki do przeniesienia)
	model:SetAttribute("Layer", layer) -- warstwa stosu (klient liczy wysokosc ghosta + walidacje stackowania)
	model:SetAttribute("FpW", fp.w)
	model:SetAttribute("FpD", fp.d)
	model.Parent = ensureUnitsFolder()
	_models[player] = _models[player] or {}
	_models[player][placementId] = model
	return model
end

local function despawnModel(player, placementId: string)
	local byPid = _models[player]
	local model = byPid and byPid[placementId]
	if model then
		model:Destroy()
		byPid[placementId] = nil
	end
end

-- ── API (§3.7) ────────────────────────────────────────────────────────────────
-- Odtworzenie plotu po ProfileLoaded: Grid.Occupy + spawn z profile.placements (BEZ Consume).
function BuildService.RestorePlot(player)
	local data = _profile.GetProfile(player)
	if not data or not data.placements then
		return
	end
	-- STACKING: odtwarzaj od DOLU (warstwa 0 pierwsza), zeby stosy zbudowaly sie w poprawnej kolejnosci.
	local order = {}
	for pid, p in pairs(data.placements) do
		order[#order + 1] = { pid = pid, p = p }
	end
	table.sort(order, function(a, b)
		return (a.p.layer or 0) < (b.p.layer or 0)
	end)
	for _, e in ipairs(order) do
		_grid.Occupy(player, e.pid, e.p.itemId, e.p.x, e.p.z, e.p.layer) -- dokladna warstwa (zachowuje "latajace")
		spawnModel(player, e.p.itemId, e.pid, e.p.x, e.p.z, e.p.rot)
	end
	BuildService.PlacementChanged:Fire(player)
end

-- Usun WSZYSTKIE jednostki gracza NARAZ (przycisk "Wyczysc dzialke"): zwrot do inventory + zwolnij grid + despawn.
-- Jedno PlacementChanged na koniec (nie po kazdej sztuce) -> klient odswieza panel raz.
function BuildService.ClearPlot(player): number
	if _wave.GetPhase(player) ~= Enums.RunPhase.Building then
		return 0
	end
	local data = _profile.GetProfile(player)
	if not data or not data.placements then
		return 0
	end
	local removed = 0
	for pid, p in pairs(data.placements) do
		_grid.Free(player, pid)
		_inv.Refund(player, p.itemId, mutObject(p.mut), p.variant or "regular")
		despawnModel(player, pid)
		data.placements[pid] = nil
		removed += 1
	end
	if removed > 0 then
		BuildService.PlacementChanged:Fire(player)
	end
	return removed
end

-- GRAWITACJA na start fali: wszystko OPADA, dziury znikaja (blok z gory spada na miejsce luki).
-- Odbudowa gridu od DOLU (wg oryginalnej warstwy): kazda jednostka siada najnizej jak sie da; zmienione respawnujemy.
function BuildService.SettleStacks(player)
	local data = _profile.GetProfile(player)
	if not data or not data.placements then
		return
	end
	local order = {}
	for pid, p in pairs(data.placements) do
		order[#order + 1] = { pid = pid, p = p }
	end
	table.sort(order, function(a, b)
		return (a.p.layer or 0) < (b.p.layer or 0)
	end)
	_grid.ResetPlayer(player)
	local changed = false
	for _, e in ipairs(order) do
		local newLayer = _grid.Occupy(player, e.pid, e.p.itemId, e.p.x, e.p.z) -- najnizej jak sie da (opada)
		if newLayer ~= (e.p.layer or 0) then
			e.p.layer = newLayer
			despawnModel(player, e.pid)
			spawnModel(player, e.p.itemId, e.pid, e.p.x, e.p.z, e.p.rot)
			changed = true
		end
	end
	if changed then
		BuildService.PlacementChanged:Fire(player)
	end
end

-- FAZA 5: jednostka zabita przez wroga (BEZ refundu). Zwalnia grid, usuwa placement, despawnuje, notyfikuje klienta.
function BuildService.KillUnit(player, placementId: string): boolean
	local data = _profile.GetProfile(player)
	local p = data and data.placements[placementId]
	if not p then
		return false
	end
	_grid.Free(player, placementId)
	despawnModel(player, placementId)
	data.placements[placementId] = nil
	Net.get("UnitKilled"):FireClient(player, { placementId = placementId })
	BuildService.PlacementChanged:Fire(player)
	return true
end

-- SNAPSHOT bazy na START fali: kopiujemy WSZYSTKIE placementy (pelne dane). WaveService wola to w beginWave
-- PO SettleStacks (warstwy juz ustabilizowane). Restore po fali odtwarza zniszczone do TEGO stanu.
function BuildService.SnapshotBase(player)
	local data = _profile and _profile.GetProfile(player)
	if not data or not data.placements then
		_snapshot[player] = nil
		return
	end
	local snap = {}
	for pid, p in pairs(data.placements) do
		snap[pid] = { itemId = p.itemId, x = p.x, z = p.z, mut = p.mut, variant = p.variant, rot = p.rot, layer = p.layer }
	end
	_snapshot[player] = snap
end

-- RESTORE bazy po fali: odtwarza jednostki/bloki ZNISZCZONE w trakcie fali (te ze snapshotu, ktorych juz nie ma).
-- Inventory NIE ruszamy (jednostka byla skonsumowana przy stawianiu; KillUnit nie refundowal -> restore = te same
-- skonsumowane sztuki wracaja na pole). Odtwarzamy od DOLU (warstwa) jak RestorePlot. HP resetuje CombatService.ResetUnitHp.
function BuildService.RestoreBase(player)
	local snap = _snapshot[player]
	if not snap then
		return
	end
	local data = _profile and _profile.GetProfile(player)
	if not data then
		return
	end
	data.placements = data.placements or {}
	local order = {}
	for pid, p in pairs(snap) do
		if data.placements[pid] == nil then -- zniszczony w fali -> odtworz
			order[#order + 1] = { pid = pid, p = p }
		end
	end
	if #order == 0 then
		return
	end
	table.sort(order, function(a, b)
		return (a.p.layer or 0) < (b.p.layer or 0)
	end)
	for _, e in ipairs(order) do
		data.placements[e.pid] = { itemId = e.p.itemId, x = e.p.x, z = e.p.z, mut = e.p.mut, variant = e.p.variant, rot = e.p.rot, layer = e.p.layer }
		_grid.Occupy(player, e.pid, e.p.itemId, e.p.x, e.p.z, e.p.layer) -- dokladna warstwa (bez re-check budzetu: restore, nie nowe stawianie)
		spawnModel(player, e.p.itemId, e.pid, e.p.x, e.p.z, e.p.rot)
	end
	BuildService.PlacementChanged:Fire(player)
end

function BuildService.Init()
	BuildService.PlacementChanged = Signal.new() -- (player)
end

function BuildService.Start()
	_inv = ServiceRegistry.get("InventoryService")
	_grid = ServiceRegistry.get("GridService")
	_plot = ServiceRegistry.get("PlotService")
	_wave = ServiceRegistry.get("WaveService")
	_profile = ServiceRegistry.get("ProfileService")

	-- normalizacja obrotu z klienta -> {0,90,180,270}
	local function normRot(rot)
		if type(rot) ~= "number" then return 0 end
		return (math.floor((rot % 360) / 90 + 0.5) % 4) * 90
	end

	-- Net.PlaceUnit (RemoteFunction): zwraca {ok, placementId?|reason?}
	Net.get("PlaceUnit").OnServerInvoke = function(player, itemId, cellX, cellZ, rot)
		if type(itemId) ~= "string" or type(cellX) ~= "number" or type(cellZ) ~= "number" then
			return { ok = false, reason = "BadArgs" }
		end
		rot = normRot(rot)
		local ok, res = doPlace(player, itemId, cellX, cellZ, rot)
		if ok then
			spawnModel(player, (select(1, parseItemId(itemId))), res, cellX, cellZ, rot)
			BuildService.PlacementChanged:Fire(player)
			return { ok = true, placementId = res }
		end
		return { ok = false, reason = res }
	end

	-- Net.MoveUnit (RemoteFunction): przenies juz postawiona jednostke -> {ok, reason?}
	Net.get("MoveUnit").OnServerInvoke = function(player, placementId, cellX, cellZ, rot)
		if type(placementId) ~= "string" or type(cellX) ~= "number" or type(cellZ) ~= "number" then
			return { ok = false, reason = "BadArgs" }
		end
		rot = normRot(rot)
		local data = _profile.GetProfile(player)
		local p = data and data.placements[placementId]
		local unitId = p and p.itemId
		local ok, reason = doMove(player, placementId, cellX, cellZ, rot)
		if ok and unitId then
			despawnModel(player, placementId)
			spawnModel(player, unitId, placementId, cellX, cellZ, rot)
			BuildService.PlacementChanged:Fire(player)
			return { ok = true }
		end
		return { ok = false, reason = reason }
	end

	-- Net.ClearPlot (RemoteFunction): usun wszystkie jednostki naraz -> {ok, removed}
	Net.get("ClearPlot").OnServerInvoke = function(player)
		local removed = BuildService.ClearPlot(player)
		return { ok = true, removed = removed }
	end

	-- Net.RemoveUnit (RemoteFunction): zwraca {ok, reason?}
	Net.get("RemoveUnit").OnServerInvoke = function(player, placementId)
		if type(placementId) ~= "string" then
			return { ok = false, reason = "BadArgs" }
		end
		local ok, reason = doRemove(player, placementId)
		if ok then
			despawnModel(player, placementId)
			BuildService.PlacementChanged:Fire(player)
			return { ok = true }
		end
		return { ok = false, reason = reason }
	end

	-- restore po zaladowaniu profilu (+ migracja: placements bez variant -> "regular")
	_profile.ProfileLoaded:Connect(function(player)
		local data = _profile.GetProfile(player)
		if data and data.placements then
			for _, p in pairs(data.placements) do
				if p.variant == nil then
					p.variant = "regular"
				end
			end
		end
		BuildService.RestorePlot(player)
	end)

	-- GRAWITACJA: na start fali bloki opadaja i wypelniaja dziury (blok z gory spada na miejsce luki)
	if _wave.WaveStarted then
		_wave.WaveStarted:Connect(function(player)
			BuildService.SettleStacks(player)
		end)
	end

	-- BUG 2B: gracz wychodzi w trakcie NIEDOKONCZONEJ fali -> jednostki zabite w tej fali (KillUnit usunal
	-- je z data.placements) maja wrocic PRZED zapisem profilu, tak samo jak przy naturalnym koncu fali.
	-- ProfileReleasing odpala sie w ProfileService.onPlayerRemoving PRZED profile:EndSession() (patrz linia
	-- 84 ProfileService) -> RestoreBase mutuje ta sama zywa tabele data ktora zaraz potem trafia do save.
	-- CELOWO NIE pod Players.PlayerRemoving w tym serwisie: BuildService startuje PO ProfileService w ORDER
	-- (init.server ORDER), wiec ten handler odpalilby sie PO profile:EndSession() — za pozno, fix by nic nie dal.
	-- Guard _restoredOnLeave: RestoreBase ma pojsc DOKLADNIE RAZ na wyjscie (idempotencja na wypadek gdyby
	-- ProfileReleasing kiedys odpalilo sie wiecej niz raz dla tego samego gracza).
	if _profile.ProfileReleasing then
		_profile.ProfileReleasing:Connect(function(player)
			if _restoredOnLeave[player] then
				warn(("[BuildService] ProfileReleasing: RestoreBase juz wywolane dla %s, pomijam duplikat"):format(player.Name))
				return
			end
			_restoredOnLeave[player] = true
			BuildService.RestoreBase(player)
			print(("[BuildService] ProfileReleasing: RestoreBase odtworzyl stan bazy przed zapisem profilu (%s)"):format(player.Name))
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		local byPid = _models[player]
		if byPid then
			for _, model in pairs(byPid) do
				model:Destroy()
			end
		end
		_models[player] = nil
		_snapshot[player] = nil
		_restoredOnLeave[player] = nil
	end)
end

-- ── Hooki TYLKO do testow (orkiestracja stanu, bez Workspace) ─────────────────
function BuildService._InjectForTest(deps)
	_inv, _grid, _plot, _wave, _profile = deps.inv, deps.grid, deps.plot, deps.wave, deps.profile
end
function BuildService._DoPlaceForTest(player, itemId, cellX, cellZ)
	return doPlace(player, itemId, cellX, cellZ)
end
function BuildService._DoRemoveForTest(player, placementId)
	return doRemove(player, placementId)
end
function BuildService._ParseItemIdForTest(itemId)
	return parseItemId(itemId)
end

return BuildService
