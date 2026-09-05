--!nonstrict
-- StarterPlayerScripts/Controllers/UnitTooltipController.luau  (KLIENT)
-- KARTA INFO gdy najedziesz na WLASNA jednostke na planszy. TYLKO w trybie wolnym (nie w budowaniu/drzewie/panelu).
--
-- user: karta ma byc 1:1 jak w edycji i pokazywac sie NA jednostce (nie kodowa nakladka nad glowa). Dlatego
-- klonujemy ZYWY oryginal Workspace.Capitan.UnitInfo (BillboardGui) i adornujemy do jednostki pod kursorem.
-- BillboardGui ma LightInfluence=0 + AlwaysOnTop -> renderuje sie tak samo wszedzie (to samo co w edycji).
-- ZERO zmian tla/koloru/przezroczystosci karty - bierzemy ja jak jest. Ustawiamy TYLKO dane: nazwa, DMG/s, HP,
-- oraz ikone 3D jednostki w PetIcon (viewport). Reszta nietkniete.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitModelFactory = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UnitModelFactory"))

local UnitTooltip = {}
local LP = Players.LocalPlayer
local WHITE = Color3.fromRGB(255, 255, 255) -- kontur jak przy najechaniu na Start Wave

local _bb = nil -- klon BillboardGui (UnitInfo) trzymany w PlayerGui, adornowany do jednostki pod kursorem
local _iconHolder, _dmgLbl, _hpLbl = nil, nil, nil
local _nameLabels = {} -- warstwowa PetName (outer+inner)
local _dmgPrefix, _hpPrefix = "DMG", "HP" -- prefiks (emoji) wyciagniety z tekstu template -> zero emoji w kodzie
local _rarityFrame = nil
local _iconCache = {}
local _curUnit = nil
local _hovered = nil
local _waveActive = false

-- 2.9K / 10.0K / 1.2M
local function fmt(n)
	n = n or 0
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n + 0.5))
end

local function statsOf(unitId)
	local u = GameConfig.Units[unitId]
	if not u then return nil end
	local dps = u.combat and (u.combat.dmg or 0) * (u.combat.fireRate or 1) or 0
	return { name = u.displayName or unitId, dps = dps, hp = u.hp or 0 }
end

-- ikona 3D jednostki (ViewportFrame), cache per unitId. Wlasne swiatlo (viewport nie bierze swiatla swiata).
local function icon(unitId)
	if _iconCache[unitId] then return _iconCache[unitId]:Clone() end
	local vpf = Instance.new("ViewportFrame")
	-- user: kafelek jednostki ma byc PRZEZROCZYSTY (przeswituje przyciemniane tlo oryginalu), nie opaque szary.
	-- Model 3D renderuje sie niezaleznie od tla; sam viewport nie ma juz wlasnej plyty.
	vpf.BackgroundTransparency = 1
	vpf.Ambient = Color3.fromRGB(255, 255, 255)
	vpf.LightColor = Color3.fromRGB(255, 255, 255)
	vpf.LightDirection = Vector3.new(-0.3, -1, -0.4)
	local vc = Instance.new("UICorner"); vc.CornerRadius = UDim.new(0, 8); vc.Parent = vpf
	local tmpl = UnitModelFactory.get(unitId)
	if tmpl then
		local cam = Instance.new("Camera"); cam.FieldOfView = 38; vpf.CurrentCamera = cam; cam.Parent = vpf
		local m = tmpl:Clone(); m.Parent = vpf
		local cf, size = m:GetBoundingBox()
		local maxd = math.max(size.X, size.Y, size.Z, 1)
		local dist = maxd * 1.45
		cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist * 0.5, size.Y * 0.22, dist), cf.Position)
	end
	_iconCache[unitId] = vpf
	return vpf:Clone()
end

-- podepnij referencje do labelek z KARTY ZIOMKA (PetWindow wewnatrz UnitInfo): PetName (outer+inner),
-- Health/Attack TextLabel, PetIcon (tu wchodzi 3D viewport), Rarity (chowany - placed units nie maja rarity).
local function wireCard(card)
	local content = card:FindFirstChild("Content", true)
	local petName = content and content:FindFirstChild("PetName")
	_nameLabels = {}
	if petName then
		if petName:IsA("TextLabel") then _nameLabels[#_nameLabels + 1] = petName end
		local inner = petName:FindFirstChild("PetName")
		if inner and inner:IsA("TextLabel") then _nameLabels[#_nameLabels + 1] = inner end
	end
	local info = content and content:FindFirstChild("Info")
	_iconHolder = info and info:FindFirstChild("PetIcon")
	if _iconHolder and _iconHolder:IsA("ImageLabel") then _iconHolder.Image = ""; _iconHolder.ImageTransparency = 1 end
	_rarityFrame = info and info:FindFirstChild("Rarity")
	if _rarityFrame then _rarityFrame.Visible = false end
	local stats = content and content:FindFirstChild("Stats")
	_hpLbl = stats and stats:FindFirstChild("Health") and stats.Health:FindFirstChild("TextLabel")
	_dmgLbl = stats and stats:FindFirstChild("Attack") and stats.Attack:FindFirstChild("TextLabel")
	_hpPrefix = (_hpLbl and _hpLbl.Text:match("^(%S+)")) or "HP"
	_dmgPrefix = (_dmgLbl and _dmgLbl.Text:match("^(%S+)")) or "DMG"
end

-- zrodlo karty 1:1: zywy Workspace.Capitan.UnitInfo (BillboardGui); fallback: ReplicatedStorage.WR_UnitInfoBB.
local function sourceBillboard()
	local cap = Workspace:FindFirstChild("Capitan")
	local ui = cap and cap:FindFirstChild("UnitInfo")
	if ui and ui:IsA("BillboardGui") then return ui end
	local rep = ReplicatedStorage:FindFirstChild("WR_UnitInfoBB")
	if rep and rep:IsA("BillboardGui") then return rep end
	-- Capitan moze byc zagniezdzony/streamowany -> szukamy UnitInfo gdziekolwiek w Workspace (rzadka sciezka)
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d.Name == "UnitInfo" and d:IsA("BillboardGui") then return d end
	end
	return nil
end

local function build()
	if _bb then return true end -- juz zbudowane
	local src = sourceBillboard()
	if not src then return false end -- brak zrodla TERAZ -> sprobujemy pozniej (leniwie w petli); hover i tak dziala
	local bb = src:Clone()
	bb.Name = "WR_UnitTip"
	bb.ResetOnSpawn = false
	bb.Adornee = nil
	bb.Enabled = false
	-- user: karta ma miec ZAWSZE ten sam rozmiar (jak z bliska), nie kurczyc sie z dystansem. Oryginal ma Size
	-- w studach ({4},{4.5}) -> skaluje sie ze swiatem. Zmieniamy KLON na PIKSELE (offset) -> BillboardGui trzyma
	-- staly rozmiar ekranowy niezaleznie od odleglosci. Proporcja jak oryginal (4:4.5). Oryginal w edycji nietkniety.
	bb.Size = UDim2.fromOffset(220, 248)
	bb.Parent = LP:WaitForChild("PlayerGui")
	local card = bb:FindFirstChild("PetWindow") or bb:FindFirstChildWhichIsA("Frame")
	if card then wireCard(card) end
	_bb = bb
	return true
end

-- czesc do adornowania: PrimaryPart -> HumanoidRootPart -> najwieksza czesc przy pivocie (rigi maja FX daleko).
local function adorneePart(m)
	if m.PrimaryPart then return m.PrimaryPart end
	local hrp = m:FindFirstChild("HumanoidRootPart", true)
	if hrp then return hrp end
	local piv = m:GetPivot().Position
	local best, bestVol = nil, -1
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and (d.Position - piv).Magnitude < 30 then
			local vol = d.Size.X * d.Size.Y * d.Size.Z
			if vol > bestVol then best, bestVol = d, vol end
		end
	end
	return best
end

-- pokaz karte NA jednostce m (unitId uid): ustaw dane (raz per unit) i zaadornuj billboard do jej czesci.
local function showOn(m, uid)
	if not _bb then return end
	local st = statsOf(uid)
	if not st then UnitTooltip.hide(); return end
	if _curUnit ~= uid then
		_curUnit = uid
		for _, lbl in ipairs(_nameLabels) do lbl.Text = st.name end
		if _iconHolder then
			for _, ch in ipairs(_iconHolder:GetChildren()) do
				if ch:IsA("ViewportFrame") then ch:Destroy() end
			end
			local ic = icon(uid)
			ic.Size = UDim2.fromScale(1, 1); ic.Position = UDim2.fromScale(0, 0); ic.Parent = _iconHolder
		end
		if _dmgLbl then _dmgLbl.Text = _dmgPrefix .. " " .. fmt(st.dps) .. "/s" end
		if _hpLbl then _hpLbl.Text = _hpPrefix .. " " .. fmt(st.hp) end
	end
	local part = adorneePart(m)
	if not part then UnitTooltip.hide(); return end
	_bb.Adornee = part
	_bb.Enabled = true
end

function UnitTooltip.hide()
	if _bb then _bb.Enabled = false; _bb.Adornee = nil end
	_curUnit = nil
end

-- biala otoczka (Highlight) na jednostce pod kursorem - sam bialy obrys, bez przyciemnienia
local function clearOutline()
	if _hovered and _hovered.Parent then
		local h = _hovered:FindFirstChild("WR_TipHL")
		if h then h:Destroy() end
	end
	_hovered = nil
end

local function setOutline(m)
	if m == _hovered then return end
	clearOutline()
	local hl = Instance.new("Highlight")
	hl.Name = "WR_TipHL"
	hl.Adornee = m
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.OutlineColor = WHITE
	hl.OutlineTransparency = 0
	hl.FillColor = Color3.new(0, 0, 0)
	hl.FillTransparency = 1
	hl.Parent = m
	_hovered = m
end

local function hideAll()
	clearOutline()
	UnitTooltip.hide()
end

-- raycast do WLASNEJ postawionej jednostki pod kursorem -> Model albo nil (w gore do atrybutu PlacementId)
local function unitUnderCursor()
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local units = Workspace:FindFirstChild("WR_Units")
	if not units then return nil end
	local mp = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mp.X, mp.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { units }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 800, params)
	if not hit then return nil end
	local m = hit.Instance
	while m and m:GetAttribute("PlacementId") == nil do m = m.Parent end
	if m and m:GetAttribute("OwnerUserId") == LP.UserId then return m end
	return nil
end

function UnitTooltip.start()
	build() -- best-effort; jak zrodla karty jeszcze nie ma, obrys i tak dziala, karta dojdzie leniwie w petli

	Net.get("WaveProgress").OnClientEvent:Connect(function() _waveActive = true end)
	Net.get("WaveEnded").OnClientEvent:Connect(function() _waveActive = false end)
	Net.get("RunSummary").OnClientEvent:Connect(function() _waveActive = false end)

	local BuildController
	local NodeTreeClient
	local function treeOpen()
		if not NodeTreeClient then
			local nt = ReplicatedStorage:FindFirstChild("NodeTree")
			local mod = nt and nt:FindFirstChild("NodeTreeClient")
			if mod then NodeTreeClient = require(mod) end
		end
		return NodeTreeClient and NodeTreeClient.isTreeVisible and NodeTreeClient.isTreeVisible() or false
	end
	local function inBuildMode()
		if not BuildController then
			local c = script.Parent:FindFirstChild("BuildController")
			if c then BuildController = require(c) end
		end
		return BuildController and BuildController.IsBuildMode and BuildController.IsBuildMode() or false
	end
	local PANELS = { "Store", "Index", "RoundOver", "OfflineEarn", "Settings" }
	local function panelOpen()
		local pg = LP.PlayerGui
		for _, name in ipairs(PANELS) do
			local g = pg:FindFirstChild(name)
			local c = g and g:FindFirstChild("Canvas")
			if c and c.Visible then return true end
		end
		return false
	end

	RunService.RenderStepped:Connect(function()
		if _waveActive or inBuildMode() or treeOpen() or panelOpen() then
			hideAll()
			return
		end
		local m = unitUnderCursor()
		if m then
			setOutline(m) -- obrys ZAWSZE (niezalezny od karty)
			if not _bb then build() end -- leniwa proba zbudowania karty gdy zrodlo juz jest
			showOn(m, m:GetAttribute("UnitId")) -- showOn samo sprawdza _bb/uid; brak karty != brak obrysu
		else
			hideAll()
		end
	end)
end

return UnitTooltip
