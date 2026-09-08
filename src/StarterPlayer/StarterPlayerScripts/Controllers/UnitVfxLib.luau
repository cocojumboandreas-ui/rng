--!nonstrict
-- StarterPlayerScripts/Controllers/UnitVfxLib.luau  (KLIENT — biblioteka, NIE controller z .start())
-- Artystyczne VFX jednostek (Workspace.VFX -> przeniesione do ReplicatedStorage.WR_UnitVfx keyed by MODEL name).
-- Zastepuja proceduralny muzzle flash+tracer w UnitCombatAnimator (gracz) i EnemyRenderController (wrog).
-- Uzywane przez OBA (te same typy jednostek sa i nasze i wroga).
--
-- Struktura WR_UnitVfx: folder per model (SWAT/Sniper/Soldier/Noob Soldier/Tank Soldier/Rocket Soldier/
-- Flamethrower/Tank/Helicopter). W kazdym Part(y) z ParticleEmitterami (Enabled=false, rate niski) + Attachment.
--   * muzzle-flash: emittery odpalane per strzal przez :Emit(n) (burst). +Y czesci = kierunek wylotu (EmissionDirection=Top).
--   * flame (Flamethrower): 1 PE Enabled=true (ciagly) + 2 Beamy -> setFlame(on/off) zamiast burst.
--   * RPG: "Rpgvfx" (flash u lufy) + "Rpgboomvfx" (wybuch u celu, speed ujemny=implozja) -> :boom(pos).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local UnitVfxLib = {}
UnitVfxLib.__index = UnitVfxLib

local FLASH_EMIT = 2 -- czastek na emitter na strzal (tuning wizualny)
local BOOM_EMIT = 3

local function root()
	return ReplicatedStorage:FindFirstChild("WR_UnitVfx")
end

-- czy mamy artystyczny VFX dla tego modelu?
function UnitVfxLib.has(modelName): boolean
	local r = root()
	return (r and modelName and r:FindFirstChild(modelName)) ~= nil
end

-- mount(parent, modelName) -> handle | nil. parent = folder swiata (render), gdzie zyje runtime-czesc VFX.
function UnitVfxLib.mount(parent, modelName)
	local r = root()
	local folder = r and modelName and r:FindFirstChild(modelName)
	if not folder then return nil end

	-- muzzle = pierwsza czesc BEZ "boom" w nazwie; boom = czesc z "boom" (szablon, klonowany przy uderzeniu)
	local muzzleTmpl, boomTmpl
	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") then
			if p.Name:lower():find("boom") then
				boomTmpl = p
			elseif not muzzleTmpl then
				muzzleTmpl = p
			end
		end
	end
	if not muzzleTmpl then return nil end

	local muzzle = muzzleTmpl:Clone()
	muzzle.Anchored = true
	muzzle.CanCollide = false; muzzle.CanQuery = false; muzzle.CanTouch = false; muzzle.CastShadow = false
	muzzle.Transparency = 1
	muzzle.Parent = parent

	local emitters, beams = {}, {}
	local flameMode = false
	for _, d in ipairs(muzzle:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			emitters[#emitters + 1] = d
			if d.Enabled then
				flameMode = true -- emitter ON w szablonie (Flamethrower) = plomien IDLE: ZOSTAJE wlaczony na stale (nie gasimy)
			end
		elseif d:IsA("Beam") then
			beams[#beams + 1] = d
			d.Enabled = false
		end
	end

	return setmetatable({
		muzzle = muzzle, emitters = emitters, beams = beams,
		boomTmpl = boomTmpl, flameMode = flameMode, parent = parent,
	}, UnitVfxLib)
end

-- ustaw world-CFrame muzzle-VFX; podajemy pozycje lufy + kierunek wylotu (world). +Y czesci -> kierunek.
function UnitVfxLib:place(muzzlePos: Vector3, dir: Vector3)
	if not (self.muzzle and self.muzzle.Parent) then return end
	local look = (dir and dir.Magnitude > 1e-3) and dir.Unit or Vector3.new(0, 0, -1)
	-- lookAt daje -Z=kierunek; obrot -90deg wokol X ustawia +Y=kierunek (EmissionDirection=Top)
	self.muzzle.CFrame = CFrame.lookAt(muzzlePos, muzzlePos + look) * CFrame.Angles(-math.pi / 2, 0, 0)
end

-- ustaw PELNY world-CFrame (flame: odtwarza dokladne ulozenie kulki-ognia z edycji — pozycja startu + kierunek strumienia/beamow).
function UnitVfxLib:placeCF(cf)
	if self.muzzle and self.muzzle.Parent then
		self.muzzle.CFrame = cf
	end
end

-- BLYSK na strzal (burst). Dla flame nie wolac — uzyj setFlame.
function UnitVfxLib:flash()
	for _, e in ipairs(self.emitters) do
		e:Emit(FLASH_EMIT)
	end
end

-- FLAME: emitter (plomien pilotujacy) jest ZAWSZE ON (ustawiony w mount) -> ogien widoczny na dyszy caly czas.
-- setFlame steruje ATAKIEM: beamy = strumien ognia do wroga (ON gdy jednostka strzela, OFF miedzy atakami).
function UnitVfxLib:setFlame(on: boolean)
	for _, b in ipairs(self.beams) do
		b.Enabled = on
	end
end

-- WYBUCH u celu (RPG/tank): klon szablonu boom w pozycji, Emit, sprzatanie przez Debris.
function UnitVfxLib:boom(worldPos: Vector3)
	if not self.boomTmpl then return end
	local b = self.boomTmpl:Clone()
	b.Anchored = true; b.CanCollide = false; b.CanQuery = false; b.CanTouch = false; b.CastShadow = false
	b.Transparency = 1
	b.CFrame = CFrame.new(worldPos)
	b.Parent = self.parent
	for _, d in ipairs(b:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			d:Emit(BOOM_EMIT)
		end
	end
	Debris:AddItem(b, 1.5)
end

-- skaluj CALY efekt (pozycje attachmentow + rozmiar czastek + predkosc) o wspolczynnik f.
-- Uzywane dla POJAZDOW wroga: szablon jest wyskalowany pod pojazd GRACZA (MainPart~10.5), a wrogi
-- pojazd ma inna skale (buildEnemyModel skaluje wg rozmiaru) -> dopasuj efekt do jego wielkosci.
function UnitVfxLib:scaleBy(f: number)
	if not (self.muzzle and self.muzzle.Parent) or math.abs(f - 1) < 1e-3 then return end
	for _, d in ipairs(self.muzzle:GetDescendants()) do
		if d:IsA("Attachment") then
			d.Position = d.Position * f
		elseif d:IsA("ParticleEmitter") then
			local kp = {}
			for _, p in ipairs(d.Size.Keypoints) do
				kp[#kp + 1] = NumberSequenceKeypoint.new(p.Time, p.Value * f, p.Envelope * f)
			end
			d.Size = NumberSequence.new(kp)
			if d.Speed.Min ~= 0 or d.Speed.Max ~= 0 then
				d.Speed = NumberRange.new(d.Speed.Min * f, d.Speed.Max * f)
			end
		end
	end
end

function UnitVfxLib:destroy()
	if self.muzzle then
		self.muzzle:Destroy()
		self.muzzle = nil
	end
end

return UnitVfxLib
