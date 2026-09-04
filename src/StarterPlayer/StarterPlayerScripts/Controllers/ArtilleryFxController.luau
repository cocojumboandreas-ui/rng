--!nonstrict
-- StarterPlayerScripts/Controllers/ArtilleryFxController.luau  (KLIENT)
-- Nalot artyleryjski: SALWA 8 rakiet (PRAWDZIWE meshe z ReplicatedStorage.WR_RocketModels) leci Z LEWEGO BOKU
-- pod katem ~45, nosem naprzod, TweenService (przyspiesza), jedna po drugiej ale szybko. Wybuch DOPIERO na
-- uderzeniu w ziemie (5 warstw) + trzesienie kamery + banner "SALWA!". 8. rakieta = artillery_booster = big.
--   Serwer autorytatywny w dmg (2k/rakieta, HP na uderzeniu) — TU tylko teatr.
--   ZERO Instance.new/Destroy per wybuch/rakiete (pule per-wariant). ZERO instancji Explosion.
-- BUDZET: ~28 czastek/wybuch (20 iskier + 8 dymu) + 3 party warstw + 1 mesh rakiety; peak salwy ~85 czastek + ~12 partow + ~4 meshe.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local ArtilleryFxController = {}
local LP = Players.LocalPlayer

local SPARKS_PER, SMOKE_PER = 20, 8
local CAP = 16
local SALVO_COUNT = 8
local STAGGER = 0.12 -- odstep miedzy rakietami (bum-bum-bum)
local FALL = 0.8 -- czas lotu rakiety (dluzej, zeby bylo widac)
local SKY_H = 95 -- wysokosc startu
local SIDE_X = 105 -- ile w lewo (start) -> kat ~45 stopni
local ROCKET_LEN = 5.2 -- docelowa dlugosc mesha rakiety (study)
local VARIANTS = { "WR_Rocket_Standard", "WR_Rocket_Interceptor", "WR_Rocket_Bomber", "WR_Rocket_Standard",
	"WR_Rocket_Interceptor", "WR_Rocket_Bomber", "WR_Rocket_Standard", "WR_Rocket_Booster" } -- 8. = booster (big)

local _fxFolder
local _pool = { flash = {}, fireball = {}, ring = {} }
local _live = { flash = 0, fireball = 0, ring = 0 }
local _emitters, _emitIdx = {}, 0
local _rocketPool = {} -- [variant] = { clones }
local _rocketLive = 0
local ROCKET_CAP = 14
local _templates = {} -- [variant] = template MeshPart

-- folder + fabryki party
local function fxFolder()
	if _fxFolder and _fxFolder.Parent then return _fxFolder end
	_fxFolder = Instance.new("Folder"); _fxFolder.Name = "WR_ArtilleryFx"; _fxFolder.Parent = Workspace
	return _fxFolder
end

local function mkPart(layer)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.Neon; p.Transparency = 1
	p.Shape = (layer == "ring") and Enum.PartType.Cylinder or Enum.PartType.Ball
	p.Parent = fxFolder()
	return p
end

local function acquire(layer)
	local p = table.remove(_pool[layer])
	if not p then
		if _live[layer] >= CAP then return nil end
		p = mkPart(layer)
	end
	_live[layer] += 1
	return p
end

local function release(layer, p)
	if p and p.Parent then p.Transparency = 1; p.CFrame = CFrame.new(0, -500, 0); table.insert(_pool[layer], p) end
	_live[layer] = math.max(0, _live[layer] - 1)
end

-- round-robin emitter (iskry + dym)
local function buildEmitter()
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Transparency = 1; p.Size = Vector3.new(0.4, 0.4, 0.4); p.CFrame = CFrame.new(0, -500, 0); p.Parent = fxFolder()
	local att = Instance.new("Attachment"); att.Parent = p
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 225, 120), Color3.fromRGB(255, 120, 40))
	sparks.LightEmission = 0.8; sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Lifetime = NumberRange.new(0.25, 0.6); sparks.Speed = NumberRange.new(28, 70)
	sparks.SpreadAngle = Vector2.new(80, 80); sparks.Rotation = NumberRange.new(0, 360)
	sparks.Acceleration = Vector3.new(0, -55, 0); sparks.Drag = 2
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparks.Rate = 0; sparks.EmissionDirection = Enum.NormalId.Top; sparks.Enabled = false; sparks.Parent = att
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Color = ColorSequence.new(Color3.fromRGB(46, 44, 42), Color3.fromRGB(28, 27, 26))
	smoke.LightEmission = 0; smoke.LightInfluence = 1; smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Lifetime = NumberRange.new(1.0, 1.5); smoke.Speed = NumberRange.new(3, 7); smoke.SpreadAngle = Vector2.new(35, 35)
	smoke.Acceleration = Vector3.new(0, 3.5, 0); smoke.Rotation = NumberRange.new(0, 360); smoke.RotSpeed = NumberRange.new(-25, 25)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 7.5) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.15, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Rate = 0; smoke.EmissionDirection = Enum.NormalId.Top; smoke.Enabled = false; smoke.Parent = att
	return { part = p, sparks = sparks, smoke = smoke }
end

local function nextEmitter()
	_emitIdx = (_emitIdx % #_emitters) + 1
	return _emitters[_emitIdx]
end

-- RAKIETA = klon prawdziwego MeshParta (dluga os X, nos -X) + Trail-ogon
local function mkRocket(variant)
	local tmpl = _templates[variant]
	local part
	if tmpl then
		part = tmpl:Clone()
		local k = ROCKET_LEN / math.max(part.Size.X, 0.01)
		part.Size = part.Size * k
	else
		part = Instance.new("Part"); part.Size = Vector3.new(ROCKET_LEN, 1.2, 1.2); part.Color = Color3.fromRGB(96, 104, 66); part.Material = Enum.Material.Metal
	end
	part.Anchored = true; part.CanCollide = false; part.CanQuery = false; part.CanTouch = false; part.CastShadow = false
	part.CFrame = CFrame.new(0, -500, 0)
	local halfX = part.Size.X * 0.5
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(halfX * 0.9, 0.35, 0); a0.Parent = part -- tyl (+X exhaust)
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(halfX * 0.9, -0.35, 0); a1.Parent = part
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0; tr.Attachment1 = a1; tr.Lifetime = 0.4; tr.LightEmission = 0.6
	tr.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(120, 120, 120))
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	tr.FaceCamera = true; tr.Parent = part
	part.Parent = fxFolder()
	return { part = part, variant = variant }
end

local function acquireRocket(variant)
	_rocketPool[variant] = _rocketPool[variant] or {}
	local rk = table.remove(_rocketPool[variant])
	if not rk then
		if _rocketLive >= ROCKET_CAP then return nil end
		rk = mkRocket(variant)
	end
	_rocketLive += 1
	return rk
end

local function releaseRocket(rk)
	if rk and rk.part then
		rk.part.CFrame = CFrame.new(0, -500, 0)
		_rocketPool[rk.variant] = _rocketPool[rk.variant] or {}
		table.insert(_rocketPool[rk.variant], rk)
	end
	_rocketLive = math.max(0, _rocketLive - 1)
end

-- CFrame rakiety: nos (-X) skierowany wzdluz `dir`, pozycja `pos`
local function rocketCf(pos, dir)
	local right = -dir.Unit -- +X = -dir  => -X (nos) = dir
	local up0 = Vector3.yAxis
	local back = right:Cross(up0)
	if back.Magnitude < 0.02 then up0 = Vector3.xAxis; back = right:Cross(up0) end
	back = back.Unit
	local up = back:Cross(right).Unit
	return CFrame.fromMatrix(pos, right, up)
end

-- TRZESIENIE KAMERY
local _shakeUntil, _shakeMag, _shakeDur = 0, 0, 0.16
local function cameraShake(mag)
	_shakeMag = math.max(_shakeMag, mag); _shakeUntil = os.clock() + _shakeDur
end

-- JEDEN WYBUCH (Flash -> Fireball -> Ring -> Smoke -> Sparks)
function ArtilleryFxController.explode(pos: Vector3, big: boolean?)
	local s = big and 2.6 or 1.7 -- wieksze wybuchy salwy (flash/fireball/ring/shake skaluja sie z s)
	do -- FLASH
		local fl = acquire("flash")
		if fl then
			local R = 9 * s
			fl.Color = Color3.fromRGB(255, 255, 255); fl.Size = Vector3.new(0.5, 0.5, 0.5); fl.CFrame = CFrame.new(pos); fl.Transparency = 0
			local light = fl:FindFirstChildOfClass("PointLight") or Instance.new("PointLight")
			light.Parent = fl; light.Color = Color3.fromRGB(255, 245, 220); light.Range = math.min(60, R * 3); light.Brightness = 15 * s; light.Enabled = true
			TweenService:Create(fl, TweenInfo.new(0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(R, R, R) }):Play()
			TweenService:Create(fl, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
			TweenService:Create(light, TweenInfo.new(0.07), { Brightness = 0 }):Play()
			task.delay(0.12, function() if light then light.Enabled = false end; release("flash", fl) end)
		end
	end
	task.delay(0.03, function() -- FIREBALL
		local fb = acquire("fireball"); if not fb then return end
		local R = 7 * s
		fb.Color = Color3.fromRGB(255, 140, 45); fb.Size = Vector3.new(0.5, 0.5, 0.5); fb.CFrame = CFrame.new(pos); fb.Transparency = 0.05
		TweenService:Create(fb, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(R * 1.1, R * 1.1, R * 1.1) }):Play()
		task.delay(0.1, function()
			if not fb.Parent then return end
			TweenService:Create(fb, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Size = Vector3.new(R * 0.9, R * 0.9, R * 0.9), Transparency = 1, Color = Color3.fromRGB(120, 45, 20) }):Play()
		end)
		task.delay(0.4, function() release("fireball", fb) end)
	end)
	do -- RING
		local rg = acquire("ring")
		if rg then
			local maxR = 22 * s
			rg.Color = Color3.fromRGB(255, 180, 90); rg.Size = Vector3.new(0.5, 4, 4)
			rg.CFrame = CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)); rg.Transparency = 0.15
			TweenService:Create(rg, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.5, maxR * 2, maxR * 2), Transparency = 1 }):Play()
			task.delay(0.45, function() release("ring", rg) end)
		end
	end
	do -- SMOKE + SPARKS
		local em = nextEmitter()
		if em then
			em.part.CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0))
			em.sparks:Emit(math.max(6, math.floor((SPARKS_PER + math.random(-4, 6)) * s)))
			task.delay(0.18, function() if em.part.Parent then em.smoke:Emit(math.floor(SMOKE_PER * s)) end end)
		end
	end
	local cam = Workspace.CurrentCamera
	if cam then
		local _, onScreen = cam:WorldToViewportPoint(pos)
		if onScreen then
			local dist = (cam.CFrame.Position - pos).Magnitude
			cameraShake(math.clamp((big and 1.6 or 1.1) * (160 / (dist + 40)), 0.06, 1.1))
		end
	end
end

-- SPADAJACA RAKIETA: z LEWEGO BOKU pod katem do impact, wybuch DOPIERO na ladowaniu
local function dropRocket(impact: Vector3, variant: string, big: boolean?)
	local rk = acquireRocket(variant)
	if not rk then ArtilleryFxController.explode(impact, big); return end
	local startP = impact + Vector3.new(-SIDE_X + math.random(-12, 12), SKY_H + math.random(-8, 8), math.random(-18, 18))
	local dir = (impact - startP).Unit
	rk.part.CFrame = rocketCf(startP, dir)
	local cfv = Instance.new("CFrameValue"); cfv.Value = rk.part.CFrame
	local conn = cfv.Changed:Connect(function() if rk.part.Parent then rk.part.CFrame = cfv.Value end end)
	local tw = TweenService:Create(cfv, TweenInfo.new(FALL, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = rocketCf(impact, dir) })
	tw.Completed:Connect(function()
		conn:Disconnect(); cfv:Destroy(); releaseRocket(rk)
		ArtilleryFxController.explode(impact, big) -- wybuch po zderzeniu z ziemia
	end)
	tw:Play()
end

-- BANNER "SALWA!"
local _bannerLbl, _bannerScale
local function banner(text)
	if not _bannerLbl then return end
	_bannerLbl.Text = text; _bannerLbl.TextTransparency = 0
	local st = _bannerLbl:FindFirstChildOfClass("UIStroke"); if st then st.Transparency = 0 end
	_bannerScale.Scale = 0.6
	TweenService:Create(_bannerScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.12 }):Play()
	task.delay(0.2, function() TweenService:Create(_bannerScale, TweenInfo.new(0.12), { Scale = 1 }):Play() end)
	task.delay(0.9, function()
		TweenService:Create(_bannerLbl, TweenInfo.new(0.45), { TextTransparency = 1 }):Play()
		if st then TweenService:Create(st, TweenInfo.new(0.45), { Transparency = 1 }):Play() end
	end)
end

-- SALWA: 8 rakiet w skupisko, jedna po drugiej, 8. = booster/big
function ArtilleryFxController.salvo(center: Vector3, radius: number?)
	radius = radius or 16
	banner("SALWA!")
	for i = 1, SALVO_COUNT do
		local big = (i == SALVO_COUNT)
		local variant = VARIANTS[i] or "WR_Rocket_Standard"
		task.delay((i - 1) * STAGGER, function()
			local ang = math.random() * 2 * math.pi
			local r = math.random() * (radius * 0.6)
			local impact = center + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
			dropRocket(impact, variant, big)
		end)
	end
end

local function makeBanner()
	local pg = LP:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_SalvoBanner"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 450; gui.Parent = pg
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5); holder.Position = UDim2.new(0.5, 0, 0.22, 0); holder.Size = UDim2.fromOffset(600, 120)
	holder.BackgroundTransparency = 1; holder.Parent = gui
	_bannerScale = Instance.new("UIScale"); _bannerScale.Scale = 1; _bannerScale.Parent = holder
	_bannerLbl = Instance.new("TextLabel")
	_bannerLbl.Size = UDim2.fromScale(1, 1); _bannerLbl.BackgroundTransparency = 1
	_bannerLbl.Font = Enum.Font.GothamBlack; _bannerLbl.TextScaled = true
	_bannerLbl.TextColor3 = Color3.fromRGB(255, 210, 70); _bannerLbl.Text = ""; _bannerLbl.TextTransparency = 1
	local st = Instance.new("UIStroke"); st.Color = Color3.new(0, 0, 0); st.Thickness = 4; st.Transparency = 1; st.Parent = _bannerLbl
	_bannerLbl.Parent = holder
end

local function loadTemplates()
	local root = ReplicatedStorage:FindFirstChild("WR_RocketModels")
	if not root then return end
	for _, model in ipairs(root:GetChildren()) do
		local mp = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChildWhichIsA("MeshPart", true)) or (model:IsA("MeshPart") and model)
		if mp then _templates[model.Name] = mp end
	end
end

function ArtilleryFxController.start()
	fxFolder()
	loadTemplates()
	for layer in pairs(_pool) do for _ = 1, 4 do table.insert(_pool[layer], mkPart(layer)) end end
	for _ = 1, 4 do _emitters[#_emitters + 1] = buildEmitter() end
	RunService:BindToRenderStep("WR_ArtShake", Enum.RenderPriority.Camera.Value + 5, function()
		if os.clock() > _shakeUntil then _shakeMag = 0; return end
		local cam = Workspace.CurrentCamera; if not cam then return end
		local remain = (_shakeUntil - os.clock()) / _shakeDur
		local m = _shakeMag * remain * remain
		cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
			* CFrame.Angles((math.random() - 0.5) * m * 0.02, (math.random() - 0.5) * m * 0.02, (math.random() - 0.5) * m * 0.02)
	end)
	makeBanner()
	-- "×N" po salwie (nagroda za skutecznosc; serwer liczy kille i wysyla SalvoResult)
	Net.get("SalvoResult").OnClientEvent:Connect(function(p)
		if type(p) == "table" and tonumber(p.kills) then banner("×" .. tostring(p.kills)) end
	end)
end

return ArtilleryFxController
