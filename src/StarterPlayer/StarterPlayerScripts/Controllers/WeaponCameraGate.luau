--!nonstrict
-- StarterPlayerScripts/Controllers/WeaponCameraGate.luau  (KLIENT)
-- TRYB STRZELANIA klawiszem [U] — dziala TYLKO w trakcie fali.
-- FILOZOFIA: kit (WeaponsSystem) jest samowystarczalny — sam robi kamere, celowanie, ADS i animacje.
-- Ten kontroler NIE dotyka kamery. Tylko:
--   * start fali -> komunikat "Press [U] to shoot" na ~5s.
--   * U -> serwer daje bronie (te 4) -> equip pierwszej -> kit sam wlacza swoj tryb (native feel).
--   * U znowu / koniec fali -> CZYSTY unequip (kit sam sprzata: kamera + animacja + celownik) -> serwer zabiera bronie.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local WeaponCameraGate = {}
local LP = Players.LocalPlayer

local _waveActive = false
local _shooting = false
local _busy = false -- debounce U (bez zacinania od podwojnego triggera)
local _msgGui, _msgLabel = nil, nil

-- kamera kitu (do awaryjnego zwolnienia przy wyjsciu, gdyby kit sam nie zdazyl)
local function releaseKitCamera()
	local wsFolder = ReplicatedStorage:FindFirstChild("WeaponsSystem")
	local mod = wsFolder and wsFolder:FindFirstChild("WeaponsSystem")
	if not mod then return end
	local ok, sys = pcall(require, mod)
	if ok and type(sys) == "table" and sys.camera and type(sys.camera.setEnabled) == "function" then
		pcall(function() sys.camera:setEnabled(false) end)
	end
end

-- equip pierwszej broni WR -> kit sam przejmuje kamere/aiming/animacje
local function equipFirstWeapon()
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if char:FindFirstChildOfClass("Tool") then return end -- juz cos trzyma
	local bp = LP:FindFirstChildOfClass("Backpack")
	local tool = bp and bp:FindFirstChildWhichIsA("Tool")
	if tool then hum:EquipTool(tool) end
end

-- czysty unequip -> kit sam zatrzymuje animacje trzymania + zwalnia kamere + chowa celownik
local function unequipAll()
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum:UnequipTools() end
	releaseKitCamera() -- fallback, gdyby kit nie zwolnil kamery sam
end

-- ustaw tryb strzelania (U). Debounce _busy => brak zacinania.
local function setShooting(on)
	if on == _shooting or _busy then return end
	_busy = true
	_shooting = on
	if on then
		Net.get("SetShootMode"):FireServer(true) -- serwer da bronie -> watcher equip
	else
		unequipAll() -- NAJPIERW czysty unequip lokalnie (kit sprzata) — bron jeszcze istnieje
		Net.get("SetShootMode"):FireServer(false) -- dopiero potem serwer zabiera bronie
	end
	task.delay(0.25, function() _busy = false end)
end

local function showMessage()
	if not _msgGui then return end
	_msgLabel.Text = "Press [U] to shoot"
	_msgGui.Enabled = true
	local token = {}
	_msgGui:SetAttribute("token", tostring(token))
	task.delay(5, function()
		if _msgGui and _msgGui:GetAttribute("token") == tostring(token) then
			_msgGui.Enabled = false
		end
	end)
end

function WeaponCameraGate.start()
	local pg = LP:WaitForChild("PlayerGui")

	-- ── komunikat "Press [U] to shoot" ──
	_msgGui = Instance.new("ScreenGui")
	_msgGui.Name = "WR_ShootHint"; _msgGui.ResetOnSpawn = false; _msgGui.IgnoreGuiInset = true
	_msgGui.DisplayOrder = 90; _msgGui.Enabled = false; _msgGui.Parent = pg
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0); frame.Position = UDim2.new(0.5, 0, 0, 120)
	frame.Size = UDim2.fromOffset(320, 44); frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	frame.BackgroundTransparency = 0.15; frame.BorderSizePixel = 0; frame.Parent = _msgGui
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 10); fc.Parent = frame
	local fs = Instance.new("UIStroke"); fs.Color = Color3.fromRGB(255, 215, 90); fs.Thickness = 2; fs.Transparency = 0.3; fs.Parent = frame
	_msgLabel = Instance.new("TextLabel")
	_msgLabel.Size = UDim2.fromScale(1, 1); _msgLabel.BackgroundTransparency = 1
	_msgLabel.Font = Enum.Font.GothamBold; _msgLabel.TextSize = 20; _msgLabel.TextColor3 = Color3.new(1, 1, 1)
	_msgLabel.Text = "Press [U] to shoot"; _msgLabel.Parent = frame

	-- ── start fali (WaveProgress killed=0 na starcie) -> komunikat + tryb dostepny ──
	Net.get("WaveProgress").OnClientEvent:Connect(function(p)
		if type(p) == "table" and (p.killed == 0 or not _waveActive) then
			_waveActive = true
			showMessage()
		end
	end)

	-- ── koniec fali / runu -> wylacz tryb + CZYSTY unequip (bez zwisu w animacji trzymania) ──
	local function onWaveEnd()
		_waveActive = false
		_busy = false
		if _shooting then
			_shooting = false
			unequipAll() -- kit sam sprzata animacje + kamere + celownik
			Net.get("SetShootMode"):FireServer(false)
		end
		if _msgGui then _msgGui.Enabled = false end
	end
	Net.get("WaveEnded").OnClientEvent:Connect(onWaveEnd)
	Net.get("RunSummary").OnClientEvent:Connect(onWaveEnd)

	-- ── klawisz U (tylko w fali) ──
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.U and _waveActive then
			setShooting(not _shooting)
		end
	end)

	-- ── bron pojawia sie w plecaku (po wlaczeniu trybu) -> equip pierwszej ──
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
