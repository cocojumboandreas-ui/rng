--!nonstrict
-- StarterPlayerScripts/Controllers/ConvoyController.luau
-- KLIENT — render KONWOJU 4 jeepow. Prawdziwy dmg = serwer (ConvoyStrikeService +
-- CombatService.GetMobileTurrets). Tu TYLKO wizual: WJAZD (offplot z lewej -> stopPos) -> POSTOJ+OGIEN
-- (bez zmian: turret aim/fire przez UnitCombatAnimator) -> WYJAZD (stopPos -> offplot w prawo) ->
-- znika. Jeden cue (ConvoyCue) niesie surowe stale formacji (linePos/lateralAxis/offsets/
-- entryExitOffset/driveT/fireT) — klient sam liczy pozycje startu/stopu/konca z tych samych stalych
-- co serwer, ktory NIE synchronizuje pozycji na biezaco w trakcie jazdy (kosmetyka, jak AtomicStrikeController).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local ConvoyController = {}

-- WaitForChild (nie FindFirstChild): to sa local-scope, wykonuja sie RAZ przy require(); jesli
-- ReplicatedStorage.Assets.Units nie zdazyl zreplikowac do klienta w tym momencie (cold start,
-- init.client leci przez ~40 kontrolerow), FindFirstChild zamrazalby TRWALE nil na cala sesje.
local ASSETS_UNITS = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Units")
local JEEP_TMPL = ASSETS_UNITS:WaitForChild("Jeep")
local GUN_TMPL = ASSETS_UNITS:WaitForChild("Dual Minigun")
local DRIVER_TMPL = ASSETS_UNITS:WaitForChild("Noob Soldier")

-- KROK 2: montaz na jeepie. Offsety mierzone LIVE wzgledem pivotu jeepa (identity rotation, nos=-Z):
--   BackBench (paka, tyl) = (0, 0.39, 4.77) -> 1 dual minigun/jeep (potwierdzone)
--   "Streeting Wheel" (kierownica) = (-1.63, 0.83, -1.06) -> kierowca Noob Soldier
-- FIX wysokosci: BackBench top ~1.35 studa nad pivotem jeepa, dziala miniguna (post ScaleTo,
-- GUN_FOOTPRINT=2.6) ~1.0 studa -> Y=2.35 stawia spod dziala na blacie paki zamiast zatapiac w ramie.
local GUN_LOCAL_OFFSET = Vector3.new(0, 2.35, 4.77)
local DRIVER_LOCAL_OFFSET = Vector3.new(-1.63, 0.83, -1.06)
local GUN_FOOTPRINT = 2.6 -- study, najwieksza krawedz po skalowaniu (dopasowane do paki jeepa)

local LocalPlayer = Players.LocalPlayer

local function worldParent()
	return Workspace:FindFirstChild("WR_FxRoot") or Workspace
end

local function unitsFolder()
	return Workspace:FindFirstChild("WR_Units")
end

-- montaz dziala jak WaveStrikeController.mkGun: PrimaryPart=mesh wiezy, wylacz fizyke, ScaleTo,
-- 180 stopni bo mesh natywnie patrzy -Z. Dziecko jeepa -> jedzie z nim sztywno przez jeep:PivotTo.
local function mountGun(jeep)
	if not GUN_TMPL then
		return nil
	end
	local g = GUN_TMPL:Clone()
	local mesh = g:FindFirstChild("WR_TurretDualMinigun")
	g.PrimaryPart = mesh
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	local _, rawSize = g:GetBoundingBox()
	local rawLen = math.max(rawSize.X, rawSize.Y, rawSize.Z)
	-- rawSize juz jest PO biezacej skali (szablon ma Scale=2.2128 z importu) -> ScaleTo jest ABSOLUTNY
	-- wzgledem oryginalnej geometrii importu, wiec trzeba pomnozyc przez biezacy GetScale(), inaczej
	-- (GUN_FOOTPRINT / rawLen) resetuje skale do dziwnego rozmiaru zamiast dopasowac do GUN_FOOTPRINT.
	g:ScaleTo(g:GetScale() * (GUN_FOOTPRINT / rawLen))
	g:PivotTo(jeep:GetPivot() * CFrame.new(GUN_LOCAL_OFFSET) * CFrame.Angles(0, math.pi, 0))
	g.Name = "MountedGun"
	g.Parent = jeep
	return g
end

-- kierowca: bez Humanoid (usuniety), CFrame-attached jak w "RNG unit weapon pose" — anchor wszystkich
-- czesci + sztywna pozycja wzgledem jeepa, zeby jechal razem przez jeep:PivotTo.
local function mountDriver(jeep)
	if not DRIVER_TMPL then
		return nil
	end
	local d = DRIVER_TMPL:Clone()
	for _, hum in ipairs(d:GetDescendants()) do
		if hum:IsA("Humanoid") then
			hum:Destroy()
		end
	end
	for _, p in ipairs(d:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	d:PivotTo(jeep:GetPivot() * CFrame.new(DRIVER_LOCAL_OFFSET))
	d.Name = "Driver"
	d.Parent = jeep
	return d
end

local function spawnJeep(pos, rot)
	if not JEEP_TMPL then
		return nil
	end
	local m = JEEP_TMPL:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	m.Parent = worldParent()
	m:PivotTo(CFrame.new(pos) * rot)
	local gun = mountGun(m)
	local driver = mountDriver(m)
	return { jeep = m, gun = gun, driver = driver }
end

-- na czas postoj+ogien wypinamy MountedGun z jeepa i wpinamy do Workspace.WR_Units z atrybutami
-- UnitId/OwnerUserId -> UnitCombatAnimator (bindFolder/ChildAdded) sam zaczyna go namierzac/celowac/strzelac
-- wizualnie (dokladnie jak realna postawiona wieza) — zero dodatkowego kodu FX. Poza oknem ognia wraca
-- jako dziecko jeepa (ChildRemoved -> untrack), zeby jechal z nim sztywno na wyjezdzie.
local function setFiring(units, on)
	local uf = unitsFolder()
	for _, unit in ipairs(units) do
		local gun = unit.gun
		if gun and gun.Parent then
			if on then
				if uf then
					gun.Parent = uf
					gun:SetAttribute("UnitId", "dual_minigun")
					gun:SetAttribute("OwnerUserId", LocalPlayer.UserId)
					gun:SetAttribute("IsConvoyTurret", true)
				end
			else
				gun:PivotTo(unit.jeep:GetPivot() * CFrame.new(GUN_LOCAL_OFFSET) * CFrame.Angles(0, math.pi, 0))
				gun.Parent = unit.jeep
			end
		end
	end
end

-- POWROT DO JAZDY (po Faza 2 kroku 4, ktory byl czysto stacjonarny): jedna wspolna "wspolrzedna
-- lateralna formacji" (NumberValue, tween przez TweenService) jedzie od -entryExitOffset (offplot z
-- lewej) do 0 (stopPos, srodek), potem od 0 do +entryExitOffset (offplot w prawo). Kazdy jeep ma
-- STALY wlasny `offset` wzgledem tej wspolrzednej (formacja sztywna, jak w kroku 4), wiec cala linia
-- jedzie razem. PivotTo niesie gun/driver jako dzieci jeepa (poza oknem ognia, patrz setFiring).
local function driveConvoy(units, cue, rot)
	local nv = Instance.new("NumberValue")
	nv.Value = -cue.entryExitOffset

	local function apply()
		local center = cue.linePos + cue.lateralAxis * nv.Value
		for i, unit in ipairs(units) do
			if unit.jeep.Parent then
				unit.jeep:PivotTo(CFrame.new(center + cue.lateralAxis * cue.offsets[i]) * rot)
			end
		end
	end
	local conn = nv:GetPropertyChangedSignal("Value"):Connect(apply)
	apply()

	local inTween = TweenService:Create(nv, TweenInfo.new(cue.driveT, Enum.EasingStyle.Linear), { Value = 0 })
	inTween:Play()
	inTween.Completed:Wait()

	setFiring(units, true)
	task.wait(cue.fireT)
	setFiring(units, false)

	local outTween =
		TweenService:Create(nv, TweenInfo.new(cue.driveT, Enum.EasingStyle.Linear), { Value = cue.entryExitOffset })
	outTween:Play()
	outTween.Completed:Wait()

	conn:Disconnect()
	nv:Destroy()
	for _, unit in ipairs(units) do
		if unit.jeep.Parent then
			unit.jeep:Destroy()
		end
	end
end

-- cue = {linePos, lateralAxis, offsets={4x}, entryExitOffset, driveT, fireT, plotId} — surowe stale
-- formacji policzone na serwerze z zywej geometrii placu (PlotService.GetPlot). Nos jeepa wskazuje
-- KIERUNEK JAZDY (lateralAxis, lewo->prawo) przez cala sekwencje — formacja jedzie bokiem, nie skreca.
local function onCue(cue)
	if type(cue) ~= "table" or typeof(cue.linePos) ~= "Vector3" or typeof(cue.lateralAxis) ~= "Vector3" then
		return
	end
	local yaw = math.atan2(-cue.lateralAxis.X, -cue.lateralAxis.Z)
	local rot = CFrame.Angles(0, yaw, 0)

	local units = {}
	for i, off in ipairs(cue.offsets) do
		local startPos = cue.linePos + cue.lateralAxis * (-cue.entryExitOffset + off)
		units[i] = spawnJeep(startPos, rot)
	end
	if #units == 0 then
		return
	end

	task.spawn(driveConvoy, units, cue, rot)
end

function ConvoyController.start()
	local cueNet = Net.get("ConvoyCue")
	cueNet.OnClientEvent:Connect(onCue)
end

return ConvoyController
