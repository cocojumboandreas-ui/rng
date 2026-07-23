--!nonstrict
-- StarterPlayerScripts/Controllers/WeaponCameraGate.luau  (KLIENT)
-- Kamera kitu broni (WeaponsSystem/ShoulderCamera) WLACZONA tylko w fali, WYLACZONA poza fala.
-- Kit ma czysty ShoulderCamera:setEnabled(true/false) — wpina/odpina render-step + rozlacza re-grab
-- (zweryfikowane: setEnabled(false) zwalnia kamere do Custom i sie utrzymuje).
-- Poza fala -> domyslna kamera Roblox (3-os, myszka, scroll zoom). W fali -> shooter kitu (celowanie PPM).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local WeaponCameraGate = {}
local LP = Players.LocalPlayer

-- kamera kitu (singleton WeaponsSystem po promocji do ReplicatedStorage); nil gdy brak broni
local function weaponCamera()
	local wsFolder = ReplicatedStorage:FindFirstChild("WeaponsSystem")
	local mod = wsFolder and wsFolder:FindFirstChild("WeaponsSystem")
	if not mod then return nil end
	local ok, sys = pcall(require, mod)
	if ok and type(sys) == "table" and sys.camera and type(sys.camera.setEnabled) == "function" then
		return sys.camera
	end
	return nil
end

local function setShoulder(on)
	local camCtrl = weaponCamera()
	if camCtrl then pcall(function() camCtrl:setEnabled(on) end) end
	if not on then
		-- twarde przywrocenie domyslnej kamery (belt-and-suspenders)
		local cam = workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Custom
			local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
			if hum then cam.CameraSubject = hum end
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		LP.CameraMode = Enum.CameraMode.Classic
	end
end

function WeaponCameraGate.start()
	-- koniec fali / runu -> zwolnij kamere kitu -> normalna kamera
	Net.get("WaveEnded").OnClientEvent:Connect(function() task.defer(setShoulder, false) end)
	Net.get("RunSummary").OnClientEvent:Connect(function() task.defer(setShoulder, false) end)

	-- bron fali pojawia sie w plecaku (start fali) -> upewnij sie ze kamera kitu wlaczona
	local function watchBackpack(bp)
		if not bp then return end
		bp.ChildAdded:Connect(function(t)
			if t:IsA("Tool") and t:GetAttribute("WR_WaveWeapon") then
				task.wait(0.3) -- pozwol WeaponsSystem sie zainicjowac po dodaniu broni
				setShoulder(true)
			end
		end)
	end
	watchBackpack(LP:FindFirstChildOfClass("Backpack"))
	LP.ChildAdded:Connect(function(c)
		if c:IsA("Backpack") then watchBackpack(c) end
	end)
end

return WeaponCameraGate
