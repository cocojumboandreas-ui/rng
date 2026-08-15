--!nonstrict
-- StarterPlayerScripts/Controllers/NukeFxLib.luau  (KLIENT — biblioteka, NIE controller z .start())
-- Wspolna FX atomowki (grzyb + kopula swiatla + shockwave + folder na czesci), wydzielona z
-- AtomicStrikeController zeby IntroController (Krok 5 finalu) mogl reuzyc DOKLADNIE ta sama FX
-- bez duplikowania kodu i bez ciagniecia orkiestracji (kamera/rakieta/bary), ktora zostaje
-- w AtomicStrikeController bo jest specyficzna dla tamtej cutscenki.
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local NukeFxLib = {}

local _fxFolder
function NukeFxLib.fxFolder(): Folder
	if _fxFolder and _fxFolder.Parent then
		return _fxFolder
	end
	_fxFolder = Instance.new("Folder")
	_fxFolder.Name = "WR_AtomicFxWorld"
	_fxFolder.Parent = Workspace
	return _fxFolder
end

local function mkPart(color, size, cf, shape, material)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = material or Enum.Material.Neon; p.Color = color; p.Size = size; p.CFrame = cf
	if shape then p.Shape = shape end
	p.Parent = NukeFxLib.fxFolder()
	return p
end

-- GRZYB ATOMOWY + KOPULA SWIATLA + SHOCKWAVE przez CALA MAPE. R=120 (bylo 90) — kolejny skok wg
-- feedbacku "jeszcze wiekszy wybuch". NOWY "lightDome": wielka niemal-nieprzezroczysta kula swiatla
-- trzymana ~2.2s (transp 0.12) po czym gasnie przez ~0.8s (razem ~3s) — "pochlania cala mape
-- swiatlem", NIEPRZEZROCZYSTE wg briefu (poprzednie warstwy za szybko gasly do pelnej przezroczystosci).
function NukeFxLib.bigMushroom(pos: Vector3)
	local R = 120

	local core = mkPart(Color3.fromRGB(255, 250, 230), Vector3.new(4, 4, 4), CFrame.new(pos), Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 245, 220); light.Range = 160; light.Brightness = 28; light.Parent = core
	TweenService:Create(core, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(R * 1.5, R * 1.5, R * 1.5) }):Play()
	TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 0 }):Play()
	task.delay(0.45, function()
		if core.Parent then
			TweenService:Create(core, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = Vector3.new(R * 0.7, R * 0.7, R * 0.7), Transparency = 1, Color = Color3.fromRGB(90, 45, 20),
			}):Play()
		end
	end)
	Debris:AddItem(core, 1.8)

	local lightDome = mkPart(Color3.fromRGB(255, 248, 225), Vector3.new(4, 4, 4), CFrame.new(pos), Enum.PartType.Ball)
	lightDome.Transparency = 0.05
	local domeLight = Instance.new("PointLight")
	domeLight.Color = Color3.fromRGB(255, 240, 210); domeLight.Range = 300; domeLight.Brightness = 12; domeLight.Parent = lightDome
	TweenService:Create(lightDome, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(R * 12, R * 12, R * 12), Transparency = 0.12,
	}):Play()
	task.delay(2.2, function()
		if lightDome.Parent then
			TweenService:Create(lightDome, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
			TweenService:Create(domeLight, TweenInfo.new(0.8), { Brightness = 0 }):Play()
		end
	end)
	Debris:AddItem(lightDome, 3.0)

	local ring = mkPart(Color3.fromRGB(255, 245, 210), Vector3.new(2, 4, 4), CFrame.new(pos + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	ring.Transparency = 0.05
	TweenService:Create(ring, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(2, R * 5, R * 5), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.7)

	local dome = mkPart(Color3.fromRGB(255, 225, 160), Vector3.new(2, 4, 4), CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	dome.Transparency = 0.05
	TweenService:Create(dome, TweenInfo.new(1.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(2, R * 8, R * 8), Transparency = 1 }):Play()
	Debris:AddItem(dome, 2.1)

	local stem = mkPart(Color3.fromRGB(230, 210, 180), Vector3.new(2, R * 0.5, R * 0.5), CFrame.new(pos + Vector3.new(0, R * 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	TweenService:Create(stem, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(R * 2.6, R * 0.42, R * 0.42), Transparency = 0.6 }):Play()
	Debris:AddItem(stem, 2.7)

	local cap = mkPart(Color3.fromRGB(255, 225, 190), Vector3.new(R * 1.1, R * 1.1, R * 1.1), CFrame.new(pos + Vector3.new(0, R * 2.4, 0)), Enum.PartType.Ball)
	cap.Transparency = 0.02
	TweenService:Create(cap, TweenInfo.new(2.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(R * 3.6, R * 2.3, R * 3.6),
		Position = pos + Vector3.new(0, R * 4.4, 0),
		Transparency = 0.55,
	}):Play()
	Debris:AddItem(cap, 3.1)
end

return NukeFxLib
