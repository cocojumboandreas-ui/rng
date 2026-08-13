--!nonstrict
-- StarterPlayerScripts/Controllers/WaveStrikeController.luau  (KLIENT — oprawa strike'ow galezi bojowej)
-- Dmg liczy serwer (WaveStrikeService); TU tylko teatr. Net.WaveStrike {kind, plotId, pos, radius}.
--   kind: "airRaid" (samolot + bomba) | "nuke" (grzyb + blysk + shockwave).
--   Military Convoy (n106) NIE idzie juz przez ten kanal — patrz ConvoyController (jeep-konwoj).
-- TEMPLATE-AWARE: jesli w ReplicatedStorage.WR_StrikeModels jest "Plane" (model z toolboxa) -> uzyj go;
--   inaczej rysuj proceduralnie (neon/part).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local WaveStrikeController = {}
local _folder = nil

local function fx()
	if _folder and _folder.Parent then
		return _folder
	end
	_folder = Instance.new("Folder")
	_folder.Name = "WR_StrikeFx"
	_folder.Parent = workspace
	return _folder
end

local function part(color, size, cf, material)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = material or Enum.Material.Neon; p.Color = color; p.Size = size; p.CFrame = cf
	p.Parent = fx()
	return p
end

local function boom(pos, color, maxR, dur)
	local ball = part(color, Vector3.new(2, 2, 2), CFrame.new(pos))
	ball.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = color; light.Range = math.min(60, maxR * 2); light.Brightness = 12; light.Parent = ball
	TweenService:Create(ball, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(maxR, maxR, maxR) * 2, Transparency = 1,
	}):Play()
	TweenService:Create(light, TweenInfo.new(dur), { Brightness = 0 }):Play()
	Debris:AddItem(ball, dur + 0.2)
end

local function shockwave(pos, maxR, color)
	local ring = part(color, Vector3.new(1, 4, 4), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)))
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.25
	TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(1, maxR * 2, maxR * 2), Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.9)
end

local function screenFlash(color, dur)
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "WR_StrikeFlash"; g.IgnoreGuiInset = true; g.DisplayOrder = 350; g.ResetOnSpawn = false; g.Parent = pg
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = color; f.BackgroundTransparency = 0.15; f.BorderSizePixel = 0; f.Parent = g
	TweenService:Create(f, TweenInfo.new(dur), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(g, dur + 0.1)
end

local function tryTemplate(name, wantLen)
	local root = ReplicatedStorage:FindFirstChild("WR_StrikeModels")
	local tmpl = root and root:FindFirstChild(name)
	if not tmpl or not tmpl:IsA("Model") then
		return nil
	end
	local m = tmpl:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
		end
	end
	local _, size = m:GetBoundingBox()
	local len = math.max(size.X, size.Z, 1)
	if wantLen and len > 0 then
		m:ScaleTo(wantLen / len)
	end
	m.Parent = fx()
	return m
end

local function flyModel(m, cfA, cfB, t)
	m:PivotTo(cfA)
	local cv = Instance.new("CFrameValue")
	cv.Value = cfA
	cv:GetPropertyChangedSignal("Value"):Connect(function()
		if m.Parent then m:PivotTo(cv.Value) end
	end)
	TweenService:Create(cv, TweenInfo.new(t, Enum.EasingStyle.Linear), { Value = cfB }):Play()
	Debris:AddItem(cv, t + 0.2)
	Debris:AddItem(m, t + 0.3)
end

-- ── NUKE ──
local function nukeFx(pos, radius)
	boom(pos, Color3.fromRGB(255, 240, 205), radius, 0.6)
	shockwave(pos, radius, Color3.fromRGB(255, 220, 150))
	local stem = part(Color3.fromRGB(255, 235, 200), Vector3.new(radius * 0.5, 6, radius * 0.5), CFrame.new(pos + Vector3.new(0, radius * 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)))
	stem.Shape = Enum.PartType.Cylinder
	TweenService:Create(stem, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(radius * 1.4, radius * 0.35, radius * 0.35), Transparency = 1,
	}):Play()
	Debris:AddItem(stem, 1.3)
	local cap = part(Color3.fromRGB(255, 230, 195), Vector3.new(radius, radius, radius), CFrame.new(pos + Vector3.new(0, radius * 1.3, 0)))
	cap.Shape = Enum.PartType.Ball
	cap.Transparency = 0.05
	TweenService:Create(cap, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(radius * 1.7, radius * 1.2, radius * 1.7),
		Position = pos + Vector3.new(0, radius * 2.1, 0), Transparency = 1,
	}):Play()
	Debris:AddItem(cap, 1.5)
	screenFlash(Color3.fromRGB(255, 250, 235), 0.5)
end

-- ── AIR RAID ──
local function planeProcedural(cf)
	local m = Instance.new("Model")
	local body = part(Color3.fromRGB(95, 100, 110), Vector3.new(16, 3, 3), cf, Enum.Material.Metal); body.Parent = m
	local wing = part(Color3.fromRGB(85, 90, 100), Vector3.new(4, 0.6, 22), cf, Enum.Material.Metal); wing.Parent = m
	local tail = part(Color3.fromRGB(85, 90, 100), Vector3.new(3, 4, 3), cf * CFrame.new(-7, 1.5, 0), Enum.Material.Metal); tail.Parent = m
	m.PrimaryPart = body
	m.Parent = fx()
	return m
end

local function airRaidFx(pos, radius)
	local h = 95
	local startP = pos + Vector3.new(-180, h, 0)
	local endP = pos + Vector3.new(180, h, 0)
	local flightT = 2.4
	local tmpl = tryTemplate("Plane", 24)
	if tmpl then
		-- model: leci POZIOMO wzdluz +X w naturalnej orientacji szablonu (bez lookAt -> nie obraca bokiem)
		flyModel(tmpl, CFrame.new(startP), CFrame.new(endP), flightT)
	else
		local startCf = CFrame.lookAt(startP, endP)
		flyModel(planeProcedural(startCf), startCf, startCf + Vector3.new(360, 0, 0), flightT)
	end
	task.delay(flightT * 0.5, function()
		local bomb = part(Color3.fromRGB(45, 45, 50), Vector3.new(1.4, 1.4, 2.8), CFrame.new(pos + Vector3.new(0, h - 4, 0)), Enum.Material.Metal)
		local fallT = 0.55
		TweenService:Create(bomb, TweenInfo.new(fallT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(pos) }):Play()
		Debris:AddItem(bomb, fallT + 0.05)
		task.delay(fallT, function()
			boom(pos, Color3.fromRGB(255, 150, 60), radius, 0.5)
			shockwave(pos, radius * 0.9, Color3.fromRGB(255, 170, 80))
		end)
	end)
end

-- NALOT = nowa salwa 8 rakiet z ArtilleryFxController (stary airRaidFx/samolot wycofany)
local function airRaidSalvo(pos, radius)
	local ok, art = pcall(function() return require(script.Parent:WaitForChild("ArtilleryFxController", 5)) end)
	if ok and art and art.salvo then art.salvo(pos, radius or 16) end
end
local HANDLERS = { airRaid = airRaidSalvo, nuke = nukeFx }

function WaveStrikeController.start()
	Net.get("WaveStrike").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" or type(p.kind) ~= "string" or typeof(p.pos) ~= "Vector3" then
			return
		end
		local h = HANDLERS[p.kind]
		if h then
			local ok, err = pcall(h, p.pos, p.radius or 12)
			if not ok then
				warn("[WaveStrikeController] FX '" .. p.kind .. "' padl: " .. tostring(err))
			end
		end
	end)
end

return WaveStrikeController
