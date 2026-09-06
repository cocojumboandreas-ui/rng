--!nonstrict
-- ReplicatedStorage/Framework/GunRig.luau
-- Wklada bron-Tool Olo (ReplicatedStorage.Guns) do PRAWEJ reki zolnierza R6 — STANDARDOWYM gripem R6,
-- dokladnie takim jak na dummy Olo (Workspace.AnimDummiesOlo): RightGrip.C0 = CFrame.new(0,-1,0)*rot,
-- C1=identity, Tool.Grip=identity. Animacje per bron (SoldierAnimConfig) pozuja rece POD ten grip -> bron
-- ladnie trzymana (dwie rece), bo animacje robione na tych dummy. Podmienia stara ad-hoc bron (submodel/part
-- o nazwie broni). Wolac PO RigAnimSetup.prepare i PO ScaleTo. Serwer (BuildService) + klient (EnemyRenderController).
local GunRig = {}

-- zolnierz (nazwa modelu) -> bron (nazwa Toola w ReplicatedStorage.Guns). Modele bez wpisu -> bez broni.
GunRig.MAP = {
	Soldier = "Rifle",
	SWAT = "Rifle",
	["Noob Soldier"] = "Pistol",
	Sniper = "Sniper",
	["Rocket Soldier"] = "RPG",
	["Tank Soldier"] = "Minigun",
	Flamethrower = "Flamethrower",
	FlameThrower = "Flamethrower",
}

-- STANDARDOWY grip R6 (wyciagniety z dummy Olo — identyczny dla wszystkich 6 broni)
local RIGHT_GRIP_C0 = CFrame.new(0, -1, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0)

-- equip(model, unitName) -> {gun, handle, muzzle} | nil. Idempotentne.
function GunRig.equip(model, unitName)
	local gunName = GunRig.MAP[unitName]
	if not gunName then return nil end
	local RS = game:GetService("ReplicatedStorage")
	local gunsF = RS:FindFirstChild("Guns")
	local tmpl = gunsF and gunsF:FindFirstChild(gunName)
	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	if not (tmpl and hum and hum.Parent) then return nil end
	local rarm = hum.Parent:FindFirstChild("Right Arm")
	if not rarm then return nil end

	-- usun stara ad-hoc bron (submodel/part o nazwie broni) + poprzedni WR_Gun/grip
	local old = model:FindFirstChild(gunName); if old then old:Destroy() end
	local prev = model:FindFirstChild("WR_Gun"); if prev then prev:Destroy() end
	local pg = rarm:FindFirstChild("WR_GunGrip"); if pg then pg:Destroy() end

	local scale = (model.GetScale and model:GetScale()) or 1

	-- klon Toola: zdejmij weldy/touch, zapamietaj relacje czesci wzgledem Handle (przed skalowaniem)
	local gun = tmpl:Clone()
	gun.Name = "WR_Gun"
	local handle = gun:FindFirstChild("Handle")
	if not handle then gun:Destroy() return nil end
	for _, d in ipairs(gun:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("TouchTransmitter") then d:Destroy() end
	end
	local hcf = handle.CFrame
	local rel = {}
	for _, p in ipairs(gun:GetChildren()) do
		if p:IsA("BasePart") then
			rel[p] = hcf:ToObjectSpace(p.CFrame)
			p.Anchored = false; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
			p.Massless = true; p.CastShadow = false
			if scale ~= 1 then p.Size = p.Size * scale end
		end
	end
	gun.Parent = model

	-- RightGrip: Handle -> Right Arm (standardowy grip, translacja skalowana dla bossow)
	local c0 = (scale ~= 1) and (CFrame.new(RIGHT_GRIP_C0.Position * scale) * RIGHT_GRIP_C0.Rotation) or RIGHT_GRIP_C0
	local grip = Instance.new("Weld")
	grip.Name = "WR_GunGrip"; grip.Part0 = rarm; grip.Part1 = handle; grip.C0 = c0; grip.C1 = CFrame.new()
	grip.Parent = rarm

	-- pozostale czesci -> Handle Weldem z JAWNYM C0 (relacja z szablonu, skalowana). NIE WeldConstraint:
	-- ten lapie offset przy aktywacji, a grip zdazyl juz przesunac Handle -> czesci wisialy setki studow obok.
	for p, r in pairs(rel) do
		if p ~= handle then
			local w = Instance.new("Weld")
			w.Part0 = handle; w.Part1 = p
			w.C0 = (scale ~= 1) and (CFrame.new(r.Position * scale) * r.Rotation) or r
			w.Parent = p
		end
	end

	local muzzle = gun:FindFirstChild("ShotPart") or gun:FindFirstChild("GunBarrel")
		or gun:FindFirstChild("MainPart") or handle
	return { gun = gun, handle = handle, muzzle = muzzle }
end

return GunRig
