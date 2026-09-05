--!nonstrict
-- StarterPlayerScripts/Controllers/WeaponCameraGate.luau  (KLIENT)
-- TRYB STRZELANIA — dziala TYLKO w trakcie fali. Wejscie przez PRZYCISK "GUNS" (na miejscu Buildu, ktory
-- i tak jest wtedy zablokowany) z wyborem broni. Wyjscie: [U] (PC) / double-tap (mobile) / Holster w panelu.
-- FILOZOFIA: kit (WeaponsSystem) jest samowystarczalny — sam robi kamere, celowanie, ADS i animacje.
-- Ten kontroler NIE dotyka kamery. Wybor broni -> serwer daje bronie (te 4) -> equip wybranej -> kit
-- sam wlacza swoj tryb. Ponowny wybor / holster / koniec fali -> CZYSTY unequip (kit sprzata).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local WeaponCameraGate = {}
local LP = Players.LocalPlayer
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local _waveActive = false
local _shooting = false
local _busy = false -- debounce U (bez zacinania od podwojnego triggera)
local _preferWeapon = nil -- bron wybrana w pickerze (equipFirstWeapon zaklada JA, nie pierwsza z brzegu)
local _lastTap = 0 -- double-tap (mobile) -> holster

-- roster broni (nazwy = nazwy Tooli w plecaku; te same co dawne skroty 1-4)
local WEAPONS = {
	{ name = "Pistol", label = "Pistol" },
	{ name = "AR", label = "Rifle" },
	{ name = "Shotgun", label = "Shotgun" },
	{ name = "Sniper", label = "Sniper" },
}

-- UI GUNS (przycisk na miejscu Buildu + panel wyboru + hint holstera)
local _gunsBtn, _gunsLabel, _picker, _pickerOpen = nil, nil, nil, false
local _buildBtn = nil -- place-owned przycisk Build (chowamy jego ikone/dim gdy GUNS widoczny)
local _weaponRows = {}
local _hintGui, _hintLabel = nil, nil

-- kamera kitu (do awaryjnego zwolnienia przy wyjsciu)
local function releaseKitCamera()
	local wsFolder = ReplicatedStorage:FindFirstChild("WeaponsSystem")
	local mod = wsFolder and wsFolder:FindFirstChild("WeaponsSystem")
	if not mod then return end
	local ok, sys = pcall(require, mod)
	if ok and type(sys) == "table" and sys.camera and type(sys.camera.setEnabled) == "function" then
		pcall(function() sys.camera:setEnabled(false) end)
	end
end

-- WZNOW kamere kitu po equipie (kit po chowaniu zostawia camera.enabled=false i sam jej nie wznawia)
local function enableKitCamera()
	local wsFolder = ReplicatedStorage:FindFirstChild("WeaponsSystem")
	local mod = wsFolder and wsFolder:FindFirstChild("WeaponsSystem")
	if not mod then return end
	local ok, sys = pcall(require, mod)
	if ok and type(sys) == "table" and sys.camera and type(sys.camera.setEnabled) == "function" then
		pcall(function() sys.camera:setEnabled(true) end)
	end
end

-- equip broni WR -> kit sam przejmuje kamere/aiming/animacje. Preferuje _preferWeapon (wybor z pickera).
local function equipFirstWeapon()
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if char:FindFirstChildOfClass("Tool") then return end -- juz cos trzyma
	local bp = LP:FindFirstChildOfClass("Backpack")
	local tool = nil
	if _preferWeapon and bp then tool = bp:FindFirstChild(_preferWeapon) end -- wybrana bron jesli juz jest
	if not tool then tool = bp and bp:FindFirstChildWhichIsA("Tool") end -- inaczej pierwsza z brzegu
	if tool then
		hum:EquipTool(tool)
		task.delay(0.3, function()
			if _shooting and LP.Character and LP.Character:FindFirstChildOfClass("Tool") then
				enableKitCamera()
			end
		end)
	end
end

local WEAPON_KEYS = {
	[Enum.KeyCode.One] = "Pistol", [Enum.KeyCode.KeypadOne] = "Pistol",
	[Enum.KeyCode.Two] = "AR", [Enum.KeyCode.KeypadTwo] = "AR",
	[Enum.KeyCode.Three] = "Shotgun", [Enum.KeyCode.KeypadThree] = "Shotgun",
	[Enum.KeyCode.Four] = "Sniper", [Enum.KeyCode.KeypadFour] = "Sniper",
}
local function equipWeaponByName(name)
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local held = char:FindFirstChildOfClass("Tool")
	if held and held.Name == name then return end -- juz trzyma te bron
	local bp = LP:FindFirstChildOfClass("Backpack")
	local tool = (bp and bp:FindFirstChild(name)) or char:FindFirstChild(name)
	if tool and tool:IsA("Tool") then
		hum:EquipTool(tool)
		task.delay(0.25, function() if _shooting then enableKitCamera() end end)
	end
end

local function unequipAll()
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum:UnequipTools() end
	releaseKitCamera()
end

-- podswietlenie wybranej broni w pickerze + kolor napisu GUNS (zielony gdy uzbrojony)
local function markSelected(name)
	for wname, row in pairs(_weaponRows) do
		row.BackgroundColor3 = (wname == name) and Color3.fromRGB(70, 150, 90) or Color3.fromRGB(40, 44, 54)
	end
	if _gunsLabel then _gunsLabel.TextColor3 = name and Color3.fromRGB(150, 255, 150) or Color3.new(1, 1, 1) end
end

-- hint jak wyjsc z trybu (PC: U, mobile: double-tap). Pojawia sie po uzbrojeniu, znika po ~4.5s.
local function showHolsterHint()
	if not _hintGui then return end
	_hintLabel.Text = IS_MOBILE and "Double-tap to holster" or "Press [U] to holster"
	_hintGui.Enabled = true
	local token = {}
	_hintGui:SetAttribute("token", tostring(token))
	task.delay(4.5, function()
		if _hintGui and _hintGui:GetAttribute("token") == tostring(token) then _hintGui.Enabled = false end
	end)
end

-- ustaw tryb strzelania. Debounce _busy => brak zacinania.
local function setShooting(on)
	if on == _shooting or _busy then return end
	_busy = true
	_shooting = on
	if on then
		Net.get("SetShootMode"):FireServer(true) -- serwer da bronie RAZ na run (jesli jeszcze nie ma)
		task.delay(0.2, function()
			if _shooting then equipFirstWeapon() end
		end)
		showHolsterHint()
	else
		_preferWeapon = nil
		unequipAll() -- CHOWA bron; bronie ZOSTAJA w plecaku (persystuja do konca runu)
		markSelected(nil)
		if _hintGui then _hintGui.Enabled = false end
	end
	task.delay(0.3, function() _busy = false end)
end

-- wybor konkretnej broni z pickera: wejdz w tryb (jesli trzeba) i zaloz TE bron; retry az Tool dojdzie z serwera
local function pickWeapon(name)
	_preferWeapon = name
	if not _shooting then
		setShooting(true)
		task.spawn(function()
			for _ = 1, 40 do
				if not _shooting or _preferWeapon ~= name then return end
				local bp = LP:FindFirstChildOfClass("Backpack")
				local char = LP.Character
				local tool = (bp and bp:FindFirstChild(name)) or (char and char:FindFirstChild(name))
				if tool then equipWeaponByName(name); return end
				task.wait(0.1)
			end
		end)
	else
		equipWeaponByName(name)
	end
	markSelected(name)
	showHolsterHint()
end

-- ── UI: przycisk GUNS (na miejscu Buildu) + panel wyboru broni ──
local function setPickerOpen(open)
	_pickerOpen = open and true or false
	if _picker then _picker.Visible = _pickerOpen end
end

-- pokaz/schowaj GUNS. Gdy widoczny: chowamy ikone/napis/dim Buildu (GUNS ma przezroczyste tlo -> nic
-- nie moze przez nie przeswiecac). task.defer -> wygrywamy z HudBindController, ktory ustawia dim na tej
-- samej klatce (start fali).
local function setGunsVisible(v)
	if _gunsBtn then _gunsBtn.Visible = v end
	if not v then setPickerOpen(false) end
	if _buildBtn then
		local icon = _buildBtn:FindFirstChild("Icon")
		local text = _buildBtn:FindFirstChild("Text")
		if icon then icon.Visible = not v end
		if text then text.Visible = not v end
		if v then
			task.defer(function()
				if _gunsBtn and _gunsBtn.Visible then
					local dim = _buildBtn:FindFirstChild("WR_BuildDim")
					if dim then dim.Visible = false end
				end
			end)
		end
	end
end

local function buildGunsUI(pg)
	-- znajdz przycisk Build (place-owned). GUNS wchodzi jako jego DZIECKO (wzorzec jak WR_BuildDim).
	local sb = pg:WaitForChild("SideButtons", 15)
	local buildBtn = sb and sb:FindFirstChild("BottomCanvas")
	buildBtn = buildBtn and buildBtn:FindFirstChild("Buttons")
	buildBtn = buildBtn and buildBtn:FindFirstChild("Build")
	_buildBtn = buildBtn

	-- przycisk GUNS: PRZEZROCZYSTE tlo (bez czarnego pudla) — sama ikona 🔫 + napis GUNS z CZARNYM konturem,
	-- jak Roll/Skills. Build pod spodem (ikona/dim) chowany w setGunsVisible.
	local btn = Instance.new("TextButton")
	btn.Name = "WR_GunsBtn"; btn.Text = ""; btn.AutoButtonColor = false
	btn.BackgroundTransparency = 1; btn.BorderSizePixel = 0; btn.ZIndex = 60; btn.Visible = false
	if buildBtn then
		btn.Size = UDim2.fromScale(1, 1); btn.Position = UDim2.fromScale(0.5, 0.5); btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Parent = buildBtn
	else
		local g = Instance.new("ScreenGui"); g.Name = "WR_GunsGui"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 95; g.Parent = pg
		btn.Size = UDim2.fromOffset(70, 70); btn.AnchorPoint = Vector2.new(0.5, 1); btn.Position = UDim2.new(0.5, 92, 1, -20); btn.Parent = g
	end
	local emoji = Instance.new("TextLabel")
	emoji.Name = "Emoji"; emoji.BackgroundTransparency = 1; emoji.Size = UDim2.fromScale(1, 0.66)
	emoji.Position = UDim2.fromScale(0.5, 0.4); emoji.AnchorPoint = Vector2.new(0.5, 0.5)
	emoji.Font = Enum.Font.GothamBold; emoji.TextScaled = true; emoji.Text = "\240\159\148\171"; emoji.ZIndex = 61 -- gun
	emoji.Parent = btn
	local es = Instance.new("UIStroke"); es.Color = Color3.fromRGB(0, 0, 0); es.Thickness = 2.5; es.Parent = emoji -- czarny kontur ikony
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"; lbl.BackgroundTransparency = 1; lbl.Size = UDim2.fromScale(1, 0.3)
	lbl.Position = UDim2.fromScale(0.5, 0.9); lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Font = Enum.Font.GothamBold; lbl.TextScaled = true; lbl.TextColor3 = Color3.new(1, 1, 1); lbl.Text = "GUNS"; lbl.ZIndex = 61
	lbl.Parent = btn
	local ls = Instance.new("UIStroke"); ls.Color = Color3.fromRGB(0, 0, 0); ls.Thickness = 2.5; ls.Parent = lbl -- czarny kontur napisu
	_gunsBtn, _gunsLabel = btn, lbl

	-- panel wyboru broni (dziecko przycisku -> unosi sie NAD nim, bez matematyki insetu)
	local panel = Instance.new("Frame")
	panel.Name = "WR_GunPicker"; panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 0, -10); panel.Size = UDim2.fromOffset(168, 4 + (#WEAPONS + 1) * 40 + 30)
	panel.BackgroundColor3 = Color3.fromRGB(24, 26, 32); panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0; panel.ZIndex = 80; panel.Visible = false; panel.Parent = btn
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 12); pc.Parent = panel
	local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(0, 0, 0); ps.Thickness = 2; ps.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 6); pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8); pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical; list.Padding = UDim.new(0, 6)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center; list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = panel
	local hdr = Instance.new("TextLabel")
	hdr.LayoutOrder = 0; hdr.Size = UDim2.new(1, 0, 0, 24); hdr.BackgroundTransparency = 1
	hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 15; hdr.TextColor3 = Color3.fromRGB(255, 220, 130); hdr.Text = "CHOOSE WEAPON"; hdr.ZIndex = 81
	hdr.Parent = panel
	local function makeRow(order, text, color, onClick)
		local r = Instance.new("TextButton")
		r.LayoutOrder = order; r.Size = UDim2.new(1, 0, 0, 34); r.AutoButtonColor = true
		r.BackgroundColor3 = color; r.BorderSizePixel = 0; r.Text = ""; r.ZIndex = 81; r.Parent = panel
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = r
		local rs = Instance.new("UIStroke"); rs.Color = Color3.fromRGB(0, 0, 0); rs.Thickness = 1.4; rs.Parent = r
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1); t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold
		t.TextSize = 17; t.TextColor3 = Color3.new(1, 1, 1); t.Text = text; t.ZIndex = 82; t.Parent = r
		r.MouseButton1Click:Connect(onClick)
		return r
	end
	_weaponRows = {}
	for i, w in ipairs(WEAPONS) do
		local row = makeRow(i, "\240\159\148\171  " .. w.label, Color3.fromRGB(40, 44, 54), function() -- gun
			pickWeapon(w.name)
			setPickerOpen(false)
		end)
		_weaponRows[w.name] = row
	end
	makeRow(#WEAPONS + 1, "\226\156\150  Holster", Color3.fromRGB(60, 40, 44), function() -- x
		setShooting(false)
		setPickerOpen(false)
	end)
	_picker = panel

	btn.MouseButton1Click:Connect(function()
		setPickerOpen(not _pickerOpen)
	end)

	-- hint holstera (toast gora-srodek) — ciemny, pojawia sie po uzbrojeniu
	_hintGui = Instance.new("ScreenGui")
	_hintGui.Name = "WR_HolsterHint"; _hintGui.ResetOnSpawn = false; _hintGui.IgnoreGuiInset = true
	_hintGui.DisplayOrder = 96; _hintGui.Enabled = false; _hintGui.Parent = pg
	local hf = Instance.new("Frame")
	hf.AnchorPoint = Vector2.new(0.5, 0); hf.Position = UDim2.new(0.5, 0, 0, 120); hf.Size = UDim2.fromOffset(300, 40)
	hf.BackgroundColor3 = Color3.fromRGB(20, 20, 28); hf.BackgroundTransparency = 0.15; hf.BorderSizePixel = 0; hf.Parent = _hintGui
	local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 10); hc.Parent = hf
	local hs = Instance.new("UIStroke"); hs.Color = Color3.fromRGB(255, 205, 90); hs.Thickness = 2; hs.Transparency = 0.3; hs.Parent = hf
	_hintLabel = Instance.new("TextLabel")
	_hintLabel.Size = UDim2.fromScale(1, 1); _hintLabel.BackgroundTransparency = 1; _hintLabel.Font = Enum.Font.GothamBold
	_hintLabel.TextSize = 18; _hintLabel.TextColor3 = Color3.new(1, 1, 1); _hintLabel.Text = ""; _hintLabel.Parent = hf
end

function WeaponCameraGate.start()
	local pg = LP:WaitForChild("PlayerGui")

	-- UKRYJ domyslny hotbar/inventory broni (po equipie bronie sa w plecaku -> Roblox pokazywal pasek).
	local StarterGui = game:GetService("StarterGui")
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	buildGunsUI(pg)

	-- ── start fali -> pokaz przycisk GUNS (zamiast dawnego komunikatu "Press [U] to shoot") ──
	Net.get("WaveProgress").OnClientEvent:Connect(function(p)
		if type(p) == "table" and not _waveActive then
			_waveActive = true -- fale leca CIAGIEM -> zostaje true do konca runu
			setGunsVisible(true)
		end
	end)

	-- ── koniec runu -> wylacz tryb + CZYSTY unequip + schowaj GUNS ──
	local function onWaveEnd()
		_waveActive = false
		_busy = false
		if _shooting then
			_shooting = false
			_preferWeapon = nil
			unequipAll()
			Net.get("SetShootMode"):FireServer(false)
		end
		setGunsVisible(false)
		markSelected(nil)
		if _hintGui then _hintGui.Enabled = false end
	end
	-- FALE CIAGIEM: NIE konczymy trybu na WaveEnded — dopiero RunSummary (pad rdzenia / reczny koniec).
	Net.get("RunSummary").OnClientEvent:Connect(onWaveEnd)

	-- ── input: U (PC toggle), double-tap (mobile holster), 1-4 (przelaczanie) ──
	UserInputService.InputBegan:Connect(function(input, gp)
		-- double-tap na ekranie (mobile) w trybie strzelania -> holster (ignoruj tapy w GUI)
		if input.UserInputType == Enum.UserInputType.Touch and _shooting and not gp then
			local now = os.clock()
			if now - _lastTap < 0.35 then
				_lastTap = 0
				setShooting(false); setPickerOpen(false)
			else
				_lastTap = now
			end
		end
		if gp then return end
		if input.KeyCode == Enum.KeyCode.U and _waveActive then
			setShooting(not _shooting) -- U: uzbrojenie / holster (hint pokazuje sie w setShooting)
			if not _shooting then setPickerOpen(false) end
		elseif _shooting then
			local wname = WEAPON_KEYS[input.KeyCode]
			if wname then pickWeapon(wname) end -- 1-4 przelacza bron
		end
	end)

	-- ── bron pojawia sie w plecaku (po wlaczeniu trybu) -> equip preferowanej/pierwszej ──
	local function watchBackpack(bp)
		if not bp then return end
		bp.ChildAdded:Connect(function(t)
			if t:IsA("Tool") and t:GetAttribute("WR_WaveWeapon") and _shooting then
				task.wait(0.1)
				equipFirstWeapon()
			end
		end)
	end
	watchBackpack(LP:FindFirstChildOfClass("Backpack"))
	LP.ChildAdded:Connect(function(c)
		if c:IsA("Backpack") then watchBackpack(c) end
	end)
end

return WeaponCameraGate
