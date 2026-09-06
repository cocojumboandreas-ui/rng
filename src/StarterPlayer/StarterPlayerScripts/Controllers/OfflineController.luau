--!nonstrict
-- StarterPlayerScripts/Controllers/OfflineController.luau  (klient)
-- Popup "Welcome back" na dolaczeniu. STERUJE designerowym StarterGui.OfflineEarn (place-owned).
-- CLAIM-GATED: serwer NIC nie przyznaje z gory — payload OfflineEarnings to PODGLAD {coins, rolls, seconds,
-- drops={{unitId,qty,oddsN}}, doubleId}. Collect (CLAIM) -> Net.ClaimOffline (x1). DoubleOffline (CLAIM X2)
-- -> DevProduct 49R (doubleId); receipt serwera przyznaje x2. Karty dropow klonowane z BestDrops.Template.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitModelFactory = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UnitModelFactory"))

local OfflineController = {}
local LP = Players.LocalPlayer

local function fmtDuration(seconds: number): string
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h > 0 then return h .. "h " .. m .. "m" end
	return m .. "m"
end

local function fmtNum(n)
	n = math.floor(tonumber(n) or 0)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
	else return tostring(n) end
end

local function resolve(root, ...)
	local cur = root
	for _, seg in ipairs({ ... }) do
		if not cur then return nil end
		cur = cur:FindFirstChild(seg)
	end
	return cur
end

-- ustaw tekst na labelu I jego zagniezdzonych labelach (kit renderuje tekst warstwowo dla obrysu)
local function setText(inst, txt)
	if not inst then return end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then inst.Text = txt end
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("TextLabel") then c.Text = txt end
	end
end

local function hide(inst) if inst then inst.Visible = false end end

-- OFFLINE COUNT-UP (jak w referencji Build a Base): licznik "+N" liczy W GORE 0 -> target przez dur sekund,
-- a karty dropow wskakuja po kolei zsynchronizowane z tym odliczaniem (patrz handler + reveal).
local OFFLINE_COUNT_DUR = 1.3
local function countUp(label, target, dur)
	if not label then return end
	target = math.max(0, math.floor((target or 0) + 0.5))
	dur = dur or OFFLINE_COUNT_DUR
	if target <= 0 or dur <= 0 then setText(label, "+" .. fmtNum(target)); return end
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local a = (os.clock() - t0) / dur
			if a >= 1 then setText(label, "+" .. fmtNum(target)); break end
			setText(label, "+" .. fmtNum(math.floor(target * a + 0.5)))
			task.wait()
		end
	end)
end

-- ikona 3D jednostki w PetIcon (ViewportFrame). SCALE-TO-FIT: cala jednostka miesci sie w kafelku (nie ucieta).
-- Gotcha: rigi maja FX (WR_Tracer/WR_Muzzle) zaparkowane ~139 studow -> GetBoundingBox puchnie i kadr sie sypie.
-- Wycinamy dalekie czesci z KLONA, liczymy CIASNY bbox z pozostalych i kadrujemy kamere pod FOV, zeby wszystko weszlo.
local function fillIcon(petIcon, unitId)
	for _, ch in ipairs(petIcon:GetChildren()) do
		if ch:IsA("ViewportFrame") then ch:Destroy() end
	end
	if petIcon:IsA("ImageLabel") then petIcon.Image = ""; petIcon.ImageTransparency = 1 end
	local tmpl = UnitModelFactory.get(unitId)
	if not tmpl then return end
	local m = tmpl:Clone()
	local piv = m:GetPivot().Position
	for _, d in ipairs(m:GetDescendants()) do -- wytnij FX zaparkowane daleko (inaczej tiny dots + zly bbox)
		if d:IsA("BasePart") and (d.Position - piv).Magnitude > 40 then d:Destroy() end
	end
	-- CIASNY AABB z pozostalych czesci (srodek + rozmiar tylko realnej jednostki)
	local minv, maxv
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local lo, hi = d.Position - d.Size * 0.5, d.Position + d.Size * 0.5
			if not minv then minv, maxv = lo, hi else
				minv = Vector3.new(math.min(minv.X, lo.X), math.min(minv.Y, lo.Y), math.min(minv.Z, lo.Z))
				maxv = Vector3.new(math.max(maxv.X, hi.X), math.max(maxv.Y, hi.Y), math.max(maxv.Z, hi.Z))
			end
		end
	end
	local center, sz
	if minv then center, sz = (minv + maxv) * 0.5, (maxv - minv) else local cf, s = m:GetBoundingBox(); center, sz = cf.Position, s end
	local vpf = Instance.new("ViewportFrame")
	vpf.Size = UDim2.fromScale(1, 1); vpf.BackgroundTransparency = 1
	vpf.Ambient = Color3.fromRGB(255, 255, 255); vpf.LightColor = Color3.fromRGB(255, 255, 255)
	vpf.LightDirection = Vector3.new(-0.3, -1, -0.4); vpf.ZIndex = 5
	local fov = 40
	local cam = Instance.new("Camera"); cam.FieldOfView = fov; vpf.CurrentCamera = cam; cam.Parent = vpf
	m.Parent = vpf
	local maxDim = math.max(sz.X, sz.Y, sz.Z, 1)
	local dist = (maxDim * 0.5) / math.tan(math.rad(fov * 0.5)) * 1.35 -- odleglosc zeby wszystko weszlo + margines
	cam.CFrame = CFrame.lookAt(center + Vector3.new(0.45, 0.22, 1).Unit * dist, center)
	vpf.Parent = petIcon
end

-- prefiks (emoji) z tekstu szablonu -> nadpisujemy tylko liczbe (zero emoji w kodzie)
local function prefixed(label, num)
	local pre = label and label.Text and label.Text:match("^(%S+)") or ""
	return pre .. " " .. num
end

-- kolor rarity (ramka + napis szans) — dopaminowo jak w referencji: rzadsze = goretsze (rozowy/czerwony), czestsze = zloto/blekit
local function rarityColor(oddsN)
	oddsN = oddsN or 0
	if oddsN >= 25000 then return Color3.fromRGB(255, 70, 130)   -- hot pink (ultra)
	elseif oddsN >= 8000 then return Color3.fromRGB(190, 100, 255) -- fiolet
	elseif oddsN >= 2500 then return Color3.fromRGB(255, 120, 60) -- pomaranczowy
	elseif oddsN >= 800 then return Color3.fromRGB(255, 205, 60)  -- zloto
	else return Color3.fromRGB(120, 215, 255) end                -- blekit (common)
end

function OfflineController.start()
	local pg = LP:WaitForChild("PlayerGui")
	local gui = pg:WaitForChild("OfflineEarn", 15)
	if not gui then
		warn("[OfflineController] brak PlayerGui.OfflineEarn — popup offline nie znaleziony")
		return
	end
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 190

	local canvas = resolve(gui, "Canvas")
	if not canvas then
		warn("[OfflineController] OfflineEarn.Canvas nie znaleziony")
		return
	end
	canvas.Visible = false

	local content = resolve(canvas, "Content", "Content")
	local moneyVal = content and resolve(content, "Values", "Money", "Value")
	local rollsVal = content and resolve(content, "Values", "Rolls", "Value")
	local offlineInfo = content and resolve(content, "OfflineInfo")
	local bestDrops = content and resolve(content, "BestDrops")
	local dropsValue = bestDrops and resolve(bestDrops, "Value")
	local template = bestDrops and bestDrops:FindFirstChild("Template")

	-- statyczne etykiety
	setText(resolve(gui, "Canvas", "IconName", "Text"), "Welcome back!")
	setText(content and resolve(content, "Values", "Money", "Text"), "Coins:")
	setText(content and resolve(content, "Values", "Rolls", "Text"), "Rolls:")

	-- odstepy listy mniejsze, zeby 5 kart + monety zmiescily sie w panelu (nie wystawaly)
	local bdLayout = bestDrops and bestDrops:FindFirstChildWhichIsA("UIListLayout")
	if bdLayout then bdLayout.Padding = UDim.new(0, 6) end
	-- schowaj szablon + ewentualne puste sloty designera (klonujemy per drop)
	if template then template.Visible = false end
	if bestDrops then
		for _, c in ipairs(bestDrops:GetChildren()) do
			if c:IsA("ImageButton") and c.Name == "Template" and c ~= template then c.Visible = false end
		end
	end

	local collect = content and resolve(content, "BottomButtons", "Collect")
	local doubleBtn = content and resolve(content, "BottomButtons", "DoubleOffline")
	local doubleId = 0
	local claimed = false

	local function claim(mult)
		if claimed then return end
		claimed = true
		if mult == 1 then
			pcall(function() Net.get("ClaimOffline"):InvokeServer() end)
		end -- x2 idzie przez receipt DevProductu (serwer sam przyzna)
		canvas.Visible = false
	end

	if collect and collect:IsA("GuiButton") then
		collect.MouseButton1Click:Connect(function() claim(1) end)
	end
	if doubleBtn and doubleBtn:IsA("GuiButton") then
		doubleBtn.MouseButton1Click:Connect(function()
			if doubleId > 0 then
				claimed = true -- zablokuj Collect; nagrode x2 da receipt serwera
				pcall(function() MarketplaceService:PromptProductPurchase(LP, doubleId) end)
				canvas.Visible = false
			end
		end)
	end
	-- CLAIM X2 ZAWSZE widoczny OBOK Collect (poziomy UIListLayout designera) i FIOLETOWY (jak referencja).
	-- Malujemy tlo + gradienty buttona na fiolet, tekst na bialo. Dziala gdy doubleId > 0 (DevProduct 49R wpisany).
	if doubleBtn then
		doubleBtn.Visible = true
		doubleBtn.BackgroundColor3 = Color3.fromRGB(150, 45, 220)
		-- FIOLETOWY gradient z WIDOCZNA glebia (pionowy gloss): jasny gora -> nasycony -> ciemny dol.
		-- (Wczesniej plaski 2-stop poziomy -> user: "gradientu nie ma". Teraz 3-stop + Rotation=90 = wyrazny.)
		local purple = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 140, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(165, 60, 235)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 22, 180)),
		})
		local white = ColorSequence.new(Color3.new(1, 1, 1))
		for _, g in ipairs(doubleBtn:GetDescendants()) do
			if g:IsA("UIGradient") then
				if g.Parent and g.Parent:IsA("TextLabel") then
					g.Color = white
				else
					g.Color = purple
					g.Rotation = 90 -- pionowy gloss: gora jasno, dol ciemno (widoczny gradient)
				end
			end
		end
	end

	-- wyczysc stare karty-klony
	local function clearCards()
		if not bestDrops then return end
		for _, c in ipairs(bestDrops:GetChildren()) do
			if c.Name == "WR_DropCard" then c:Destroy() end
		end
	end

	local function makeCard(drop, order)
		if not template then return end
		local u = GameConfig.Units[drop.unitId]
		local card = template:Clone()
		card.Name = "WR_DropCard"; card.Visible = true; card.LayoutOrder = order; card.Parent = bestDrops
		-- rozroznij labele Text po pozycji Y: dol = NAZWA; gora = ILOSC -> przenosimy w LEWY gorny rog "xN" (jak ref)
		for _, t in ipairs(card:GetChildren()) do
			if t:IsA("TextLabel") and t.Name == "Text" then
				if t.Position.Y.Scale > 0.5 then
					setText(t, u and u.displayName or drop.unitId)
				else
					setText(t, "x" .. drop.qty)
					t.AnchorPoint = Vector2.new(0, 0); t.Position = UDim2.fromScale(0.06, 0.04)
					t.Size = UDim2.fromScale(0.5, 0.2); t.TextXAlignment = Enum.TextXAlignment.Left
					t.Rotation = 0; t.ZIndex = 12
				end
			end
		end
		-- staty z configu (dps = dmg*fireRate, hp)
		local atk = resolve(card, "Stats", "Attack", "TextLabel")
		local hpL = resolve(card, "Stats", "Health", "TextLabel")
		local dps = (u and u.combat) and (u.combat.dmg or 0) * (u.combat.fireRate or 1) or 0
		if atk then setText(atk, prefixed(atk, fmtNum(dps) .. "/s")) end
		if hpL then setText(hpL, prefixed(hpL, fmtNum(u and u.hp or 0))) end
		-- ikona 3D
		local petIcon = card:FindFirstChild("PetIcon")
		if petIcon then fillIcon(petIcon, drop.unitId) end
		-- RAMKA kolorowana rarity (jak w referencji: rzadsze = goretszy kolor)
		local col = rarityColor(drop.oddsN)
		local frameStroke = card:FindFirstChildWhichIsA("UIStroke")
		if frameStroke then
			frameStroke.Color = col
			frameStroke.Thickness = math.max(frameStroke.Thickness, 3)
			local grad = frameStroke:FindFirstChildWhichIsA("UIGradient")
			if grad then grad.Color = ColorSequence.new(col, col:Lerp(Color3.new(1, 1, 1), 0.45)) end
		end
		-- szanse "1 in N" — gruby, kolorowany rarity, po skosie, czarny obrys (dopamina jak w referencji)
		local odds = Instance.new("TextLabel")
		odds.Name = "WR_Odds"; odds.BackgroundTransparency = 1; odds.AnchorPoint = Vector2.new(1, 0)
		odds.Position = UDim2.new(1, 2, 0, -3); odds.Size = UDim2.fromScale(0.7, 0.19); odds.Rotation = 12
		odds.Font = Enum.Font.GothamBlack; odds.TextScaled = true; odds.TextXAlignment = Enum.TextXAlignment.Right
		odds.TextColor3 = col; odds.Text = "1 in " .. fmtNum(drop.oddsN or 0); odds.ZIndex = 12
		local os_ = Instance.new("UIStroke"); os_.Color = Color3.fromRGB(20, 15, 25); os_.Thickness = 2.6; os_.LineJoinMode = Enum.LineJoinMode.Round; os_.Parent = odds
		odds.Parent = card
		-- pop-in: UIScale=1 TERAZ (fit mierzy pelny rozmiar); staggered reveal (0->1) odpala handler po zmierzeniu
		local pop = Instance.new("UIScale"); pop.Name = "WR_Pop"; pop.Scale = 1; pop.Parent = card
	end

	Net.get("OfflineEarnings").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" or ((p.coins or 0) <= 0 and (p.rolls or 0) <= 0) then
			return
		end
		claimed = false
		doubleId = tonumber(p.doubleId) or 0
		countUp(moneyVal, p.coins or 0, OFFLINE_COUNT_DUR) -- licznik liczy W GORE (jak referencja)
		countUp(rollsVal, p.rolls or 0, OFFLINE_COUNT_DUR)
		setText(offlineInfo, ("While you were away (%s), you earned:"):format(fmtDuration(p.seconds or 0)))
		if dropsValue then setText(dropsValue, "+" .. fmtNum(p.coins or 0)); dropsValue.LayoutOrder = 999 end -- monety NA KONCU rzedu (jak ref)

		-- drops
		local drops = type(p.drops) == "table" and p.drops or {}
		clearCards()
		if bestDrops then bestDrops.Visible = #drops > 0 end
		for i, d in ipairs(drops) do makeCard(d, i) end

		-- FIT: przeskaluj CALA liste (karty + "+N") jednym UIScale, zeby zmiescila sie w panelu (nie wystawala
		-- z lewej/prawej). Mierzymy naturalna szerokosc po klatce, potem ustawiamy scale <= 1.
		if bestDrops then
			local scaleObj = bestDrops:FindFirstChild("WR_FitScale") or Instance.new("UIScale")
			scaleObj.Name = "WR_FitScale"; scaleObj.Scale = 1; scaleObj.Parent = bestDrops
			task.defer(function()
				if not (bestDrops and bestDrops.Parent) then return end
				local lay2 = bestDrops:FindFirstChildWhichIsA("UIListLayout")
				local pad2 = (lay2 and lay2.Padding.Offset) or 0
				local sumW, cnt = 0, 0
				for _, c in ipairs(bestDrops:GetChildren()) do
					if c.Name == "WR_DropCard" or (c.Name == "Value" and c:IsA("GuiObject") and c.Visible) then
						sumW += c.AbsoluteSize.X; cnt += 1
					end
				end
				local content = sumW + math.max(0, cnt - 1) * pad2
				local panel = bestDrops.AbsoluteSize.X
				scaleObj.Scale = (content > panel and panel > 0) and math.clamp((panel - 6) / content, 0.4, 1) or 1
				-- STAGGERED REVEAL: karty pojawiaja sie PO KOLEI (pop 0->1 z Back), nie naraz (jak Build a Base RNG)
				local cards = {}
				for _, c in ipairs(bestDrops:GetChildren()) do
					if c.Name == "WR_DropCard" then cards[#cards + 1] = c end
				end
				table.sort(cards, function(a, b) return (a.LayoutOrder or 0) < (b.LayoutOrder or 0) end)
				for _, c in ipairs(cards) do
					local pp = c:FindFirstChild("WR_Pop")
					if pp then pp.Scale = 0 end
				end
				-- karty rozlozone na czas COUNT-UP (ostatnia wpada tuz przed koncem odliczania) — sync jak referencja
				local step = (#cards > 0) and math.clamp(OFFLINE_COUNT_DUR * 0.8 / #cards, 0.08, 0.26) or 0.1
				for i, c in ipairs(cards) do
					local pp = c:FindFirstChild("WR_Pop")
					if pp then
						task.delay((i - 1) * step, function()
							if pp.Parent then
								TweenService:Create(pp, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
							end
						end)
					end
				end
			end)
		end

		-- CLAIM X2 zawsze widoczny obok Collect (fiolet ustawiony w start); klik dziala gdy doubleId > 0

		canvas.Visible = true
	end)
end

return OfflineController
