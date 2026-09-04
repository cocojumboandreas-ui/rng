--!nonstrict
-- StarterPlayerScripts/Controllers/RollRevealController.luau  (post-bramka task 4 — KLIENT-ONLY)
-- Reveal rolki + kaskada mutacji. Sterowany Net.RollResult (serwer juz rzuca mutacje od Task 5).
-- Fazy (timingi z RevealConfig §4 per revealTier): dim -> build-up (deszcz koniczyn=luck) ->
--   [jesli mutation] kaskada x2->x4->x8 -> reveal jednostki na starburscie ("1 in N" + nazwa) -> settle.
-- Intensywnosc skaluje revealTier (DERYWOWANY z rarityN przez RarityConfig — payload go nie ma).
-- Object pooling elementow VFX (zero Instance.new spam per roll). v1 LEAN — poprawna STRUKTURA faz.
-- Trigger: tymczasowy przycisk ROLL (fires RollRequest). Docelowa "zajebista" animacja Andreasa = polish.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)
local UnitModelFactory = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UnitModelFactory"))
local RollReelReveal = require(script.Parent:WaitForChild("RollReelReveal"))

-- Flaga reveala: true = nowy reel (slot machine); false = stary starburst (zachowany, osiagalny).
local REEL_REVEAL = true

local RARITY_COLOR = {
	[1] = Color3.fromRGB(185, 185, 195), -- common
	[2] = Color3.fromRGB(90, 200, 120), -- rare
	[3] = Color3.fromRGB(90, 160, 255), -- super rare
	[4] = Color3.fromRGB(195, 110, 255), -- mystic
	[5] = Color3.fromRGB(255, 205, 80), -- legend
	[6] = Color3.fromRGB(230, 60, 70), -- mysterious
}

-- ── KONICZYNY-MNOZNIKI (kaskada jak w referencji port.mp4) ──
-- Biala koniczyna (tintowalna ImageColor3). Warstwa czarna z tylu = kontur.
local CLOVER_ASSET = "rbxassetid://11999300080"
-- mult -> kolor szczebla. x64 = nil -> tecza (animowany UIGradient).
local CLOVER_COLOR = {
	[2] = Color3.fromRGB(70, 210, 70), -- zielony
	[4] = Color3.fromRGB(60, 150, 255), -- niebieski
	[8] = Color3.fromRGB(255, 195, 35), -- zloty
	[16] = Color3.fromRGB(180, 80, 255), -- fioletowy
	[32] = Color3.fromRGB(255, 55, 55), -- czerwony
	[64] = nil, -- tecza
	[128] = nil, -- tecza (fallback wyzej)
}
local RAINBOW_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(0.20, Color3.fromRGB(255, 200, 40)),
	ColorSequenceKeypoint.new(0.40, Color3.fromRGB(70, 220, 70)),
	ColorSequenceKeypoint.new(0.60, Color3.fromRGB(50, 200, 255)),
	ColorSequenceKeypoint.new(0.80, Color3.fromRGB(140, 90, 255)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 70, 200)),
})

-- FINISH wariantu (warstwa poza kaskada mutacji). regular = brak. galaxy rzadszy -> mocniejszy.
local VARIANT_FINISH = {
	shiny = { text = "✨ SHINY ✨", color = Color3.fromRGB(255, 240, 150), extraHold = 0.4 },
	galaxy = { text = "🌌 GALAXY 🌌", color = Color3.fromRGB(150, 120, 255), extraHold = 1.0, strong = true },
}

local RollRevealController = {}

local _stage, _dim, _revealBox, _burst, _titleLbl, _nameLbl, _cascadeHolder, _finishLbl
local _cloverRow, _popSound -- warstwa koniczyn + dzwiek "pop" lancucha
local _cloverPool = {}
local _queue = {}
local _playing = false

-- BRAMKA anty-spam: jeden roll naraz. Klik ustawia _rollBusy natychmiast (blokuje kolejne kliki jeszcze
-- przed startem reveala), a koniec reveala (callback playRoll) czysci flage. Generacja unieważnia stary bezpiecznik.
local _rollBusy = false
local _rollGen = 0
function RollRevealController.requestRoll()
	if _rollBusy then return end -- trwa roll -> zignoruj klik
	_rollBusy = true
	_rollGen += 1
	local myGen = _rollGen
	Net.get("RollRequest"):FireServer()
	task.delay(12, function() if myGen == _rollGen then _rollBusy = false end end) -- bezpiecznik gdy serwer nie odpowie
end

-- ── helpers ──
local function deriveTier(rarityN: number): number
	for _, t in ipairs(GameConfig.Rarity.tiers) do
		if rarityN <= t.maxN then
			return t.revealTier
		end
	end
	return 6
end

-- resolver dla RollReelReveal: rarityN -> { color, name } (kolor tieru + nazwa rzadkosci)
local function resolveTier(rarityN: number)
	for _, t in ipairs(GameConfig.Rarity.tiers) do
		if rarityN <= t.maxN then
			return { color = RARITY_COLOR[t.revealTier] or RARITY_COLOR[1], name = t.name }
		end
	end
	local last = GameConfig.Rarity.tiers[#GameConfig.Rarity.tiers]
	return { color = RARITY_COLOR[6], name = last and last.name or "Mysterious" }
end

local function params(tier: number)
	local rc = GameConfig.Reveal.tiers
	if rc[tier] then
		return rc[tier]
	end
	for t = tier, 1, -1 do -- floor do najblizszego zdefiniowanego (2->1, 4->3)
		if rc[t] then
			return rc[t]
		end
	end
	return rc[1]
end

local function tween(obj, t, props, style)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- kaskada: mnozniki od x2 do mult
local function rungsFor(mult: number)
	local r = {}
	local m = 2
	while m <= mult do
		r[#r + 1] = "×" .. m
		m *= 2
	end
	return r
end

-- ── pooling koniczyn ──
local function acquireClover()
	local c = table.remove(_cloverPool)
	if not c then
		c = Instance.new("TextLabel")
		c.BackgroundTransparency = 1
		c.Font = Enum.Font.GothamBold
		c.Text = "🍀"
		c.TextScaled = true
		c.Size = UDim2.fromOffset(38, 38)
		c.ZIndex = 3
		c.Parent = _stage
	end
	c.Visible = true
	c.TextTransparency = 0
	return c
end
local function releaseClover(c)
	c.Visible = false
	table.insert(_cloverPool, c)
end

-- ── fazy ──
local function rainClovers(count: number, duration: number)
	for i = 1, count do
		task.spawn(function()
			local c = acquireClover()
			local x = math.random(5, 90) / 100
			c.Position = UDim2.new(x, 0, -0.1, 0)
			c.Rotation = math.random(-40, 40)
			local fall = duration * (0.6 + math.random() * 0.5)
			tween(c, fall, { Position = UDim2.new(x, 0, 1.1, 0), Rotation = c.Rotation + math.random(-90, 90) }, Enum.EasingStyle.Linear)
			task.wait(fall * 0.7)
			tween(c, fall * 0.3, { TextTransparency = 1 })
			task.wait(fall * 0.3)
			releaseClover(c)
		end)
		task.wait(duration / count * 0.5)
	end
end

local function playCascade(mult: number, color: Color3)
	local rungs = rungsFor(mult)
	for i, txt in ipairs(rungs) do
		local icon = _cascadeHolder:FindFirstChild("R" .. i)
		if not icon then
			icon = Instance.new("TextLabel")
			icon.Name = "R" .. i
			icon.BackgroundTransparency = 1
			icon.Font = Enum.Font.GothamBlack
			icon.TextSize = 44
			icon.Size = UDim2.fromOffset(90, 60)
			icon.Position = UDim2.new(0.5, (i - #rungs / 2 - 0.5) * 96 + 48, 0.5, 0)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.ZIndex = 6
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(255, 230, 120)
			stroke.Thickness = 2
			stroke.Parent = icon
			icon.Parent = _cascadeHolder
		end
		icon.Text = txt
		icon.TextColor3 = color
		icon.Visible = true
		icon.TextTransparency = 0
		icon.Size = UDim2.fromOffset(20, 14)
		tween(icon, 0.18, { Size = UDim2.fromOffset(96, 64) }, Enum.EasingStyle.Back)
		task.wait(0.26)
	end
	task.wait(0.15)
end

-- ══════════════ KASKADA KONICZYN (zywy roll, oprawa jak port.mp4) ══════════════
-- Koniczyny + listki budowane PROCEDURALNIE z UI (4-5 platkow), tintowalne per szczebel.
-- ZERO zaleznosci od assetu (Decal nie renderuje sie w ImageLabel). Ruch w calosci na TweenService.
local LOBE_POS = { -- glowka w gornych ~65% (dol zostawiony na LODYGE)
	Vector2.new(0.5, 0.2), Vector2.new(0.7, 0.4),
	Vector2.new(0.5, 0.6), Vector2.new(0.3, 0.4), Vector2.new(0.5, 0.4),
}
local PETAL_POS = {
	Vector2.new(0.5, 0.28), Vector2.new(0.72, 0.5), Vector2.new(0.5, 0.72), Vector2.new(0.28, 0.5),
}
local function mkCircle(parent, sizeScale, pos, color, zi)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(pos.X, pos.Y)
	f.Size = UDim2.fromScale(sizeScale, sizeScale)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = zi
	local uc = Instance.new("UICorner")
	uc.CornerRadius = UDim.new(1, 0)
	uc.Parent = f
	f.Parent = parent
	return f
end

-- Male listki = MINI-KONICZYNY (4 platki) — pula, tintowalne w kolorze szczebla.
local _petalPool = {}
local function acquirePetal()
	local p = table.remove(_petalPool)
	if not p then
		p = Instance.new("Frame")
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.BackgroundTransparency = 1
		p.Size = UDim2.fromOffset(20, 20)
		p.ZIndex = 4
		p.Parent = _stage
		for _, pos in ipairs(PETAL_POS) do
			mkCircle(p, 0.6, pos, Color3.new(1, 1, 1), 4)
		end
	end
	p.Visible = true
	return p
end
local function releasePetal(p)
	p.Visible = false
	table.insert(_petalPool, p)
end
local function tintPetal(p, color)
	for _, l in ipairs(p:GetChildren()) do
		if l:IsA("Frame") then
			l.BackgroundColor3 = color
			l.BackgroundTransparency = 0
		end
	end
end
local function fadePetal(p, dur)
	for _, l in ipairs(p:GetChildren()) do
		if l:IsA("Frame") then
			tween(l, dur, { BackgroundTransparency = 1 })
		end
	end
end

-- Duza koniczyna-mnoznik (CanvasGroup: 5 czarnych konturow + 5 platkow + liczba Nx) — pula.
local _bigCloverPool = {}
local function acquireBigClover()
	local c = table.remove(_bigCloverPool)
	if not c then
		c = Instance.new("Frame")
		c.BackgroundTransparency = 1
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Size = UDim2.fromOffset(96, 96)
		c.ZIndex = 6
		c.Parent = _cloverRow
		local cg = Instance.new("CanvasGroup")
		cg.Name = "CG"
		cg.BackgroundTransparency = 1
		cg.Size = UDim2.fromScale(1, 1)
		cg.ZIndex = 6
		cg.Parent = c
		-- LODYGA (za glowka): czarny kontur + kolorowy trzon
		local stemO = Instance.new("Frame")
		stemO.Name = "StemO"; stemO.AnchorPoint = Vector2.new(0.5, 0); stemO.Position = UDim2.fromScale(0.5, 0.5)
		stemO.Size = UDim2.fromScale(0.2, 0.48); stemO.BackgroundColor3 = Color3.new(0, 0, 0); stemO.BorderSizePixel = 0; stemO.ZIndex = 5; stemO.Parent = cg
		local sco = Instance.new("UICorner"); sco.CornerRadius = UDim.new(0.45, 0); sco.Parent = stemO
		local stem = Instance.new("Frame")
		stem.Name = "Stem"; stem.AnchorPoint = Vector2.new(0.5, 0); stem.Position = UDim2.fromScale(0.5, 0.52)
		stem.Size = UDim2.fromScale(0.12, 0.44); stem.BackgroundColor3 = Color3.fromRGB(90, 160, 60); stem.BorderSizePixel = 0; stem.ZIndex = 5; stem.Parent = cg
		local scc = Instance.new("UICorner"); scc.CornerRadius = UDim.new(0.45, 0); scc.Parent = stem
		for i, pos in ipairs(LOBE_POS) do
			mkCircle(cg, (i == 5 and 0.46 or 0.52), pos, Color3.new(0, 0, 0), 6) -- kontur (czarny, wiekszy)
		end
		for i, pos in ipairs(LOBE_POS) do
			local l = mkCircle(cg, (i == 5 and 0.36 or 0.44), pos, Color3.new(1, 1, 1), 7) -- platek
			l.Name = "Lobe" .. i
			local g = Instance.new("UIGradient") -- szklisty polysk: jasniej u gory, ciemniej u dolu
			g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150)) })
			g.Rotation = 90; g.Parent = l
		end
		local num = Instance.new("TextLabel")
		num.Name = "Num"
		num.BackgroundTransparency = 1
		num.Size = UDim2.fromScale(1, 0.36)
		num.Position = UDim2.fromScale(0, 0.22)
		num.Font = Enum.Font.GothamBlack
		num.TextScaled = true
		num.TextColor3 = Color3.new(1, 1, 1)
		num.ZIndex = 9
		num.Parent = cg
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Color = Color3.new(0, 0, 0)
		st.Parent = num
	end
	local cg = c:FindFirstChild("CG")
	cg.GroupTransparency = 0
	c.Visible = true
	return c
end
local function releaseBigClover(c)
	c.Visible = false
	local cg = c:FindFirstChild("CG")
	if cg then cg.GroupTransparency = 0 end
	table.insert(_bigCloverPool, c)
end
local function tintClover(c, color)
	local cg = c:FindFirstChild("CG")
	if not cg then return end
	for i = 1, 5 do
		local l = cg:FindFirstChild("Lobe" .. i)
		if l then l.BackgroundColor3 = color end
	end
	local stem = cg:FindFirstChild("Stem")
	if stem then stem.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.35) end -- lodyga = ciemniejszy odcien
end

-- Wystrzal mini-koniczyn z miejsca koniczyny (X=skala, Y=skala).
local function burstConfetti(color, cxScale, cy)
	for _ = 1, 12 do
		task.spawn(function()
			local p = acquirePetal()
			tintPetal(p, color)
			local sz = math.random(16, 26)
			p.Size = UDim2.fromOffset(sz, sz)
			p.Rotation = math.random(0, 360)
			p.Position = UDim2.new(cxScale, 0, cy, 0)
			local ang = math.random() * math.pi * 2
			local dist = math.random(40, 120)
			local ox = math.cos(ang) * dist
			tween(p, 0.22, { Position = UDim2.new(cxScale, ox, cy + math.sin(ang) * dist * 0.006, 0) }, Enum.EasingStyle.Quad)
			task.wait(0.22)
			local fall = 0.5 + math.random() * 0.4
			tween(p, fall, { Position = UDim2.new(cxScale, ox + math.random(-30, 30), 1.15, 0), Rotation = p.Rotation + math.random(-120, 120) }, Enum.EasingStyle.Quad)
			task.delay(fall * 0.7, function() fadePetal(p, fall * 0.3) end)
			task.wait(fall)
			releasePetal(p)
		end)
	end
end

-- Ambient: mini-koniczyny leca Z GORY NA DOL przez caly ekran (kolory obecnych szczebli).
local function rainPetals(colors, duration, count)
	task.spawn(function()
		for _ = 1, count do
			local p = acquirePetal()
			tintPetal(p, colors[math.random(1, #colors)])
			local x = math.random(3, 97) / 100
			local sz = math.random(14, 24)
			p.Size = UDim2.fromOffset(sz, sz)
			p.Rotation = math.random(0, 360)
			p.Position = UDim2.new(x, 0, -0.1, 0)
			local fall = duration * (0.55 + math.random() * 0.5)
			tween(p, fall, { Position = UDim2.new(x, math.random(-40, 40), 1.15, 0), Rotation = p.Rotation + math.random(-120, 120) }, Enum.EasingStyle.Linear)
			task.delay(fall * 0.75, function() fadePetal(p, fall * 0.25) end)
			task.delay(fall, function() releasePetal(p) end)
			task.wait(duration / count)
		end
	end)
end

local X0, DX, Y_ROW = 0.12, 0.085, 0.42 -- rzad koniczyn: lewo->srodek (itemy ida PO PRAWEJ)
-- Sloty odslon itemow (modele na gwiazdach) rozrzucone PO PRAWEJ (skala) — jak port.mp4.
local ITEM_SLOTS = {
	Vector2.new(0.64, 0.42), -- 1: PROMINENTNY (center-prawo), reszta rozrzucona
	Vector2.new(0.83, 0.28), Vector2.new(0.85, 0.56),
	Vector2.new(0.71, 0.68), Vector2.new(0.92, 0.42),
	Vector2.new(0.75, 0.22), Vector2.new(0.93, 0.66),
}
-- CIEPLE gwiazdy jak w filmiku (nie szare): zloto -> pomarancz -> czerwien wg rzadkosci.
local STAR_TIER = {
	[1] = Color3.fromRGB(255, 205, 70), [2] = Color3.fromRGB(255, 205, 70), [3] = Color3.fromRGB(255, 175, 45),
	[4] = Color3.fromRGB(255, 120, 40), [5] = Color3.fromRGB(255, 60, 60),
}

local function fmtOdds(nR)
	if nR >= 1e6 then return string.format("1 in %.1fM", nR / 1e6) end
	if nR >= 1000 then return string.format("1 in %.1fK", nR / 1000) end
	return "1 in " .. tostring(math.floor(nR))
end

-- ViewportFrame z modelem itemu (jak RollReelReveal): klon + kamera na bbox.
local function buildViewport(model, parent)
	local vpf = Instance.new("ViewportFrame")
	vpf.BackgroundTransparency = 1
	local cam = Instance.new("Camera"); vpf.CurrentCamera = cam; cam.Parent = vpf
	local clone = model:Clone(); clone.Parent = vpf
	local cframe, size = clone:GetBoundingBox()
	local dist = math.max(size.X, size.Y, size.Z, 1) * 1.7
	cam.CFrame = CFrame.new(cframe.Position + Vector3.new(0, size.Y * 0.08, dist), cframe.Position)
	vpf.Parent = parent
	return vpf
end

-- Kolczasta GWIAZDA (sunburst) z proceduralnych promieni (tintowalna). Zwraca Frame "SB".
local function buildStarburst(parent)
	local sb = Instance.new("Frame")
	sb.Name = "SB"; sb.BackgroundTransparency = 1; sb.AnchorPoint = Vector2.new(0.5, 0.5)
	sb.Position = UDim2.fromScale(0.5, 0.45); sb.Size = UDim2.fromScale(1.35, 1.35); sb.ZIndex = 7
	for i = 1, 10 do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"; ray.AnchorPoint = Vector2.new(0.5, 0.5); ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromScale(0.32, 1.1); ray.Rotation = i * 36; ray.BorderSizePixel = 0
		ray.BackgroundColor3 = Color3.fromRGB(255, 200, 60); ray.ZIndex = 7; ray.Parent = sb
		local g = Instance.new("UIGradient") -- zwezenie do szpica: przezroczyste konce, jasny srodek
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.12), NumberSequenceKeypoint.new(1, 1) })
		g.Rotation = 90; g.Parent = ray
	end
	sb.Parent = parent
	return sb
end

-- Odslona itemu = gwiazda + model (viewport) + rzadkosc "1 in N" nad + nazwa pod. Pula.
local _itemPool = {}
local function acquireItemReveal()
	local f = table.remove(_itemPool)
	if not f then
		f = Instance.new("Frame")
		f.BackgroundTransparency = 1; f.AnchorPoint = Vector2.new(0.5, 0.5); f.Size = UDim2.fromOffset(130, 130); f.ZIndex = 7; f.Parent = _cloverRow
		buildStarburst(f)
		local od = Instance.new("TextLabel")
		od.Name = "Odds"; od.BackgroundTransparency = 1; od.AnchorPoint = Vector2.new(0.5, 1); od.Position = UDim2.fromScale(0.5, 0.12)
		od.Size = UDim2.fromScale(1, 0.2); od.Font = Enum.Font.GothamBlack; od.TextScaled = true; od.ZIndex = 9; od.Parent = f
		local s1 = Instance.new("UIStroke"); s1.Thickness = 2; s1.Color = Color3.new(0, 0, 0); s1.Parent = od
		local nm = Instance.new("TextLabel")
		nm.Name = "Nm"; nm.BackgroundTransparency = 1; nm.AnchorPoint = Vector2.new(0.5, 0); nm.Position = UDim2.fromScale(0.5, 0.92)
		nm.Size = UDim2.fromScale(1.3, 0.2); nm.Font = Enum.Font.GothamBold; nm.TextScaled = true; nm.TextColor3 = Color3.new(1, 1, 1); nm.ZIndex = 9; nm.Parent = f
		local s2 = Instance.new("UIStroke"); s2.Thickness = 2; s2.Color = Color3.new(0, 0, 0); s2.Parent = nm
	end
	f.Visible = true
	return f
end
local function releaseItemReveal(f)
	f.Visible = false
	local vp = f:FindFirstChild("VP"); if vp then vp:Destroy() end
	table.insert(_itemPool, f)
end

-- Odslania item ogniwa: gwiazda w kolorze rzadkosci + MODEL 3D + "1 in N" + nazwa. ZOSTAJE (persistuje).
local function revealItem(step, idx)
	local slot = ITEM_SLOTS[((idx - 1) % #ITEM_SLOTS) + 1]
	local tier = deriveTier(step.rarityN)
	local scol = STAR_TIER[tier] or STAR_TIER[1]
	local unit = GameConfig.Units[step.unitId]
	local nm = (unit and unit.displayName) or step.unitId
	local bigPx = (idx == 1) and 210 or 128 -- pierwszy item = duzy (focal), reszta mniejsze
	local f = acquireItemReveal()
	local sb = f:FindFirstChild("SB")
	for _, ray in ipairs(sb:GetChildren()) do
		if ray.Name == "Ray" then ray.BackgroundColor3 = scol; ray.BackgroundTransparency = 0 end
	end
	local od, nmL = f:FindFirstChild("Odds"), f:FindFirstChild("Nm")
	od.Text = fmtOdds(step.rarityN); od.TextColor3 = scol; od.TextTransparency = 0
	nmL.Text = nm; nmL.TextTransparency = 0
	local tmpl = UnitModelFactory.get(step.unitId)
	if tmpl then
		local vpf = buildViewport(tmpl, f)
		vpf.Name = "VP"; vpf.AnchorPoint = Vector2.new(0.5, 0.5); vpf.Position = UDim2.fromScale(0.5, 0.45); vpf.Size = UDim2.fromScale(0.72, 0.72); vpf.ZIndex = 8
	end
	f.Position = UDim2.new(slot.X, 0, slot.Y, 0)
	f.Size = UDim2.fromOffset(40, 40)
	tween(f, 0.25, { Size = UDim2.fromOffset(bigPx, bigPx) }, Enum.EasingStyle.Back)
	tween(sb, 3.0, { Rotation = 30 }, Enum.EasingStyle.Linear)
	return f
end

-- Dzwiek "pop" per szczebel (wyzszy ton = wyzsza koniczyna) — eskalacja.
local function playPop(i)
	if _popSound then
		_popSound.PlaybackSpeed = 0.9 + math.min(i, 7) * 0.09
		_popSound.TimePosition = 0
		_popSound:Play()
	end
end

-- Sekwencja KROK-PO-KROKU (realny LANCUCH z serwera): koniczyna x(2^i) wpada z gory (+pop),
-- a jej ITEM odslania sie jako MODEL na gwiezdzie po prawej i ZOSTAJE. Wszystko na TweenService.
local function playCloverCascade(chain)
	local n = #chain
	if n == 0 then return end
	local live = {}
	for i, step in ipairs(chain) do
		local xScale = X0 + (i - 1) * DX
		local mult = step.mult
		local c, cg = nil, nil
		if mult then -- ten roll dal koniczyne
			c = acquireBigClover()
			cg = c:FindFirstChild("CG")
			local num = cg:FindFirstChild("Num")
			local color = CLOVER_COLOR[mult]
			num.Text = math.floor(mult) .. "x"
			local rainbow = (color == nil) -- x64+ = tecza (hue-cycle)
			tintClover(c, color or Color3.new(1, 1, 1))
			if rainbow then color = Color3.fromRGB(255, 120, 220) end -- confetti dla teczy
			c.Position = UDim2.new(xScale, 0, -0.15, 0) -- start nad swoja kolumna
			c.Size = UDim2.fromOffset(96, 96)
			-- SPADEK z gory (TweenService, overshoot=Back) — CZEKAMY az osiadzie zanim ruszy nastepna
			tween(c, 0.45, { Position = UDim2.new(xScale, 0, Y_ROW, 0) }, Enum.EasingStyle.Back)
			task.wait(0.45)
			playPop(i) -- POP przy ladowaniu (ton rosnie ze szczeblem)
			tween(c, 0.10, { Size = UDim2.fromOffset(112, 84) }, Enum.EasingStyle.Quad) -- squash
			task.wait(0.10)
			tween(c, 0.14, { Size = UDim2.fromOffset(96, 96) }, Enum.EasingStyle.Back)
			burstConfetti(color, xScale, Y_ROW)
			if rainbow then -- hue-cycle platkow dopoki widoczna
				task.spawn(function()
					while c.Visible do
						tintClover(c, Color3.fromHSV((os.clock() * 0.6) % 1, 0.85, 1))
						RunService.Heartbeat:Wait()
					end
				end)
			end
		end
		local itemF = revealItem(step, i) -- MODEL itemu na gwiezdzie po prawej (zostaje)
		live[#live + 1] = { c = c, cg = cg, item = itemF }
		task.wait(0.16) -- beat -> "nowy roll" -> nastepne ogniwo
	end
	-- caly rzad + itemy zostaja chwile -> potem znikaja RAZEM (plynnie, TweenService)
	task.wait(2.2) -- rzad + itemy zostaja chwile na ekranie
	for _, e in ipairs(live) do
		task.spawn(function()
			if e.c then tween(e.c, 0.3, { Size = UDim2.fromOffset(60, 60) }, Enum.EasingStyle.Quad) end
			if e.cg then tween(e.cg, 0.3, { GroupTransparency = 1 }) end
			local it = e.item
			tween(it, 0.3, { Size = UDim2.fromOffset(70, 70) })
			for _, ch in ipairs(it:GetDescendants()) do
				if ch:IsA("Frame") and ch.Name == "Ray" then
					tween(ch, 0.3, { BackgroundTransparency = 1 })
				elseif ch:IsA("TextLabel") then
					tween(ch, 0.3, { TextTransparency = 1 })
				elseif ch:IsA("ViewportFrame") then
					tween(ch, 0.3, { ImageTransparency = 1 })
				end
			end
			task.wait(0.32)
			if e.c then releaseBigClover(e.c) end
			releaseItemReveal(it)
		end)
	end
end

local function playReveal(result)
	local tier = deriveTier(result.rarityN)
	local p = params(tier)
	local color = RARITY_COLOR[tier] or RARITY_COLOR[1]
	local unit = GameConfig.Units[result.unitId]
	local name = (unit and unit.displayName) or result.unitId

	-- reset stage
	for _, c in ipairs(_cascadeHolder:GetChildren()) do
		if c:IsA("TextLabel") then c.Visible = false end
	end
	_revealBox.Visible = false

	-- 1) DIM
	_dim.Visible = true
	tween(_dim, 0.18, { BackgroundTransparency = 0.45 })
	task.wait(0.18)

	-- 2) BUILD-UP (deszcz koniczyn = luck) — gestosc skaluje tierem
	local cloverCount = tier >= 5 and 22 or (tier >= 3 and 14 or 6)
	task.spawn(rainClovers, cloverCount, p.buildupSec)
	task.wait(p.buildupSec)

	-- 3) KASKADA MUTACJI (tylko jesli mutation)
	if result.mutation and result.mutation.mult and p.cascade ~= false then
		playCascade(result.mutation.mult, color)
	end

	-- 4) REVEAL na starburscie
	_titleLbl.Text = "1 in " .. tostring(result.rarityN)
	_titleLbl.TextColor3 = color
	_nameLbl.Text = result.mutation and (name .. "  (×" .. result.mutation.mult .. ")") or name
	local fin = VARIANT_FINISH[result.variant] -- shiny/galaxy; nil dla regular
	_burst.TextColor3 = (fin and fin.strong) and fin.color or color -- galaxy tintuje burst
	_revealBox.Visible = true
	_revealBox.Size = UDim2.fromScale(0.05, 0.05)
	_burst.Rotation = 0
	local big = tier >= 5 or (fin and fin.strong) -- galaxy dostaje wiekszy reveal
	tween(_revealBox, 0.32, { Size = UDim2.fromScale(big and 0.72 or 0.5, big and 0.5 or 0.36) }, Enum.EasingStyle.Back)
	tween(_burst, p.holdSec + 0.4, { Rotation = big and 90 or 30 }, Enum.EasingStyle.Linear)

	-- FINISH wariantu (obok kaskady mutacji)
	if fin then
		_finishLbl.Text = fin.text
		_finishLbl.TextColor3 = fin.color
		_finishLbl.Visible = true
		_finishLbl.TextTransparency = 1
		tween(_finishLbl, 0.3, { TextTransparency = 0 })
	else
		_finishLbl.Visible = false
	end
	task.wait(p.holdSec + (fin and fin.extraHold or 0))

	-- 5) SETTLE
	tween(_revealBox, 0.25, { Size = UDim2.fromScale(0.05, 0.05) })
	if _finishLbl.Visible then
		tween(_finishLbl, 0.25, { TextTransparency = 1 })
	end
	tween(_dim, 0.3, { BackgroundTransparency = 1 })
	task.wait(0.3)
	_revealBox.Visible = false
	_finishLbl.Visible = false
	_dim.Visible = false
end

local function pump()
	if _playing then
		return
	end
	_playing = true
	task.spawn(function()
		while #_queue > 0 do
			local result = table.remove(_queue, 1)
			local ok, err = pcall(playReveal, result)
			if not ok then
				warn("[RollReveal] " .. tostring(err))
			end
		end
		_playing = false
	end)
end

function RollRevealController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_RollReveal"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000 -- nad reveal packa (RollGui=999), by kaskada koniczyn byla widoczna
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	_dim = Instance.new("Frame")
	_dim.Size = UDim2.fromScale(1, 1); _dim.BackgroundColor3 = Color3.new(0, 0, 0)
	_dim.BackgroundTransparency = 1; _dim.BorderSizePixel = 0; _dim.ZIndex = 1
	_dim.Visible = false; _dim.Parent = gui

	_stage = Instance.new("Frame") -- warstwa VFX (koniczyny)
	_stage.Size = UDim2.fromScale(1, 1); _stage.BackgroundTransparency = 1
	_stage.ZIndex = 2; _stage.Parent = gui

	_cloverRow = Instance.new("Frame") -- warstwa duzych koniczyn-mnoznikow (nad confetti)
	_cloverRow.Size = UDim2.fromScale(1, 1); _cloverRow.BackgroundTransparency = 1
	_cloverRow.ZIndex = 6; _cloverRow.Parent = gui

	_popSound = Instance.new("Sound") -- "pop" per szczebel koniczyny (ton rosnie)
	_popSound.SoundId = "rbxassetid://15675055424" -- Roblox_UI_Cute_Pop
	_popSound.Volume = 0.55
	_popSound.Parent = gui

	_cascadeHolder = Instance.new("Frame")
	_cascadeHolder.Size = UDim2.fromScale(1, 0.3); _cascadeHolder.Position = UDim2.fromScale(0, 0.28)
	_cascadeHolder.BackgroundTransparency = 1; _cascadeHolder.ZIndex = 5; _cascadeHolder.Parent = gui

	_revealBox = Instance.new("Frame")
	_revealBox.AnchorPoint = Vector2.new(0.5, 0.5); _revealBox.Position = UDim2.fromScale(0.5, 0.5)
	_revealBox.Size = UDim2.fromScale(0.5, 0.36); _revealBox.BackgroundTransparency = 1
	_revealBox.ZIndex = 8; _revealBox.Visible = false; _revealBox.Parent = gui

	_burst = Instance.new("TextLabel") -- starburst (emoji ✦, skalowany+obrot)
	_burst.Size = UDim2.fromScale(1, 1); _burst.AnchorPoint = Vector2.new(0.5, 0.5)
	_burst.Position = UDim2.fromScale(0.5, 0.5); _burst.BackgroundTransparency = 1
	_burst.Font = Enum.Font.GothamBlack; _burst.Text = "✦"; _burst.TextScaled = true
	_burst.TextTransparency = 0.35; _burst.ZIndex = 8; _burst.Parent = _revealBox

	_titleLbl = Instance.new("TextLabel")
	_titleLbl.Size = UDim2.fromScale(0.9, 0.16); _titleLbl.Position = UDim2.fromScale(0.05, 0.3)
	_titleLbl.BackgroundTransparency = 1; _titleLbl.Font = Enum.Font.GothamBlack; _titleLbl.TextScaled = true
	_titleLbl.Text = ""; _titleLbl.ZIndex = 9; _titleLbl.Parent = _revealBox

	_nameLbl = Instance.new("TextLabel")
	_nameLbl.Size = UDim2.fromScale(0.9, 0.14); _nameLbl.Position = UDim2.fromScale(0.05, 0.52)
	_nameLbl.BackgroundTransparency = 1; _nameLbl.Font = Enum.Font.GothamBold; _nameLbl.TextScaled = true
	_nameLbl.TextColor3 = Color3.new(1, 1, 1); _nameLbl.Text = ""; _nameLbl.ZIndex = 9; _nameLbl.Parent = _revealBox

	-- FINISH wariantu (shiny/galaxy) — nad boxem reveala, wyrazny
	_finishLbl = Instance.new("TextLabel")
	_finishLbl.Size = UDim2.fromScale(0.8, 0.08); _finishLbl.Position = UDim2.fromScale(0.1, 0.16)
	_finishLbl.AnchorPoint = Vector2.new(0, 0)
	_finishLbl.BackgroundTransparency = 1; _finishLbl.Font = Enum.Font.GothamBlack; _finishLbl.TextScaled = true
	_finishLbl.Text = ""; _finishLbl.ZIndex = 10; _finishLbl.Visible = false; _finishLbl.Parent = gui
	local fstroke = Instance.new("UIStroke"); fstroke.Color = Color3.new(0, 0, 0); fstroke.Thickness = 2; fstroke.Parent = _finishLbl

	-- przycisk ROLL = KOSTKA (ikona z packa "RNG Roll"), wpieta pod nasz RollRequest.
	local rollBtn = Instance.new("ImageButton")
	-- HUD: dol-srodek, kwadratowa kostka
	rollBtn.Size = UDim2.fromOffset(112, 112); rollBtn.AnchorPoint = Vector2.new(0.5, 1)
	rollBtn.Position = UDim2.new(0.5, 0, 1, -14)
	rollBtn.BackgroundTransparency = 1
	rollBtn.Image = "rbxassetid://92245991358603" -- kostka (RollButton.Icon z dema Roll v1.0)
	rollBtn.ScaleType = Enum.ScaleType.Fit
	rollBtn.ZIndex = 40
	rollBtn.Parent = gui
	rollBtn.Visible = false -- STARY tymczasowy Roll ukryty; rolluje przycisk ziomka (SideButtons.Roll)
	-- napis "Roll" na dole kostki (jak w packu)
	local rbName = Instance.new("TextLabel")
	rbName.Size = UDim2.new(1, 0, 0, 22); rbName.AnchorPoint = Vector2.new(0.5, 1)
	rbName.Position = UDim2.new(0.5, 0, 0.98, 0)
	rbName.BackgroundTransparency = 1; rbName.Text = "Roll"; rbName.TextColor3 = Color3.new(1, 1, 1)
	rbName.Font = Enum.Font.GothamBlack; rbName.TextSize = 20; rbName.ZIndex = 41; rbName.Parent = rollBtn
	local rbStroke = Instance.new("UIStroke"); rbStroke.Thickness = 2; rbStroke.Color = Color3.new(0, 0, 0); rbStroke.Parent = rbName
	rollBtn.MouseButton1Click:Connect(function()
		Net.get("RollRequest"):FireServer()
	end)
	-- klik-feedback: lekkie wcisniecie
	rollBtn.MouseButton1Down:Connect(function()
		rollBtn.Size = UDim2.fromOffset(102, 102)
	end)
	rollBtn.MouseButton1Up:Connect(function()
		rollBtn.Size = UDim2.fromOffset(112, 112)
	end)

	-- reel-reveal (slot machine): dekoje = wszystkie rollowalne unitId; model = UnitModelFactory
	local decoyIds = {}
	for id in pairs(GameConfig.Units) do
		decoyIds[#decoyIds + 1] = id
	end
	RollReelReveal.init({
		parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		resolveTier = resolveTier,
		modelProvider = UnitModelFactory.get,
		decoyIds = decoyIds,
		starburstId = "", -- repo uzywa tekstowego bursta (✦), brak asset id -> aura niewidoczna
		onRollAgain = function() RollRevealController.requestRoll() end, -- Rolka/Auto w pasku reveala (gated)
	})

	-- reveal packa "RNG Roll" sterowany NASZYM wynikiem (nasze modele w viewport + audio packa).
	-- Stary RollReelReveal wylaczony (ich wyglad zamiast naszego).
	local RollClient = require(game:GetService("ReplicatedStorage"):WaitForChild("Roll"):WaitForChild("RollClient"))
	RollClient.setBaseRollTime(2.5) -- czas reveala (snappy)

	-- buduje format packa (kolumny koniczyn Bonus -> finalny Item) z jednego wyniku serwera
	local function reelFromResult(r)
		local columns = {}
		if r.chain then
			for _, step in ipairs(r.chain) do
				if step.mult then
					columns[#columns + 1] = { rollItemType = "Bonus", mult = step.mult } -- koniczyna-mnoznik
				end
			end
		end
		-- special ("gold"/"diamond"/"rainbow") na FINALNYM itemie -> pack podkresla zwyciezke (aura+badge)
		columns[#columns + 1] = { itemId = r.unitId, rollItemType = "Item", special = r.special }
		return { columns = columns }
	end

	Net.get("RollResult").OnClientEvent:Connect(function(result)
		if type(result) ~= "table" then
			return
		end
		-- Double Roll: serwer moze przyslac { multi = { wynik1, wynik2 } } -> 2 rownolegle reele + 2 itemy.
		-- Normalna rolka: pojedynczy wynik -> znormalizuj do tablicy 1-elementowej.
		local reelsIn = result.multi or { result }
		local rollResults = {}
		for _, r in ipairs(reelsIn) do
			if type(r) == "table" and r.unitId then
				rollResults[#rollResults + 1] = reelFromResult(r)
			end
		end
		if #rollResults == 0 then
			return
		end
		-- RollResult = WYLACZNIE manualny pipe (auto leci przez RequestRollRemoteFunction, nigdy tutaj).
		-- Manual Roll zawsze otwiera czarna makiete, niezaleznie od globalnego auto ON/OFF; sticky
		-- bo auto-roll (RollClient.requestRoll) nigdy nie dotyka _isCompact po tym momencie.
		RollClient.setIsCompact(false)
		RollClient.playRolls(rollResults, function()
			_rollBusy = false -- reveal (wszystkie reele) zakonczony -> mozna rollowac ponownie
			-- WR fix: po manualnym rollu ZWIN makiete do compact -> guziki Hide/Auto znikaja z ekranu
			-- (bez tego _isCompact zostawal false i przyciski wisialy w zwyklej grze po skonczonym rollu).
			-- Auto-roll (requestRoll) leci osobnym pipe i tak w compact, wiec zwiniecie mu nie przeszkadza.
			RollClient.setIsCompact(true)
		end)
	end)
end

-- Hooki TYLKO do testow (headless sanity: sekwencja odpala, pooling zwalnia).
function RollRevealController._QueueForTest(result)
	if #_queue < 6 then
		_queue[#_queue + 1] = result
	end
	pump()
end
function RollRevealController._StateForTest()
	return { playing = _playing, queueLen = #_queue, cloverPool = #_cloverPool }
end

return RollRevealController
