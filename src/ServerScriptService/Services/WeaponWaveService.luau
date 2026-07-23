--!nonstrict
-- ServerScriptService/Services/WeaponWaveService.luau
-- Bronie FPS gracza dostepne TYLKO na czas fali: WaveStarted -> daj do plecaka; WaveEnded -> zabierz.
-- Poza fala brak broni -> WeaponsSystem/ShoulderCamera nieaktywna -> domyslna kamera 3-os (scroll do 1-os).
-- W fali: gracz moze wziac bron -> celowanie/strzelanie (kit ma zoom scroll 1<->3 osoba).
-- Szablony broni: ServerStorage.WR_WaveWeapons (przeniesione ze StarterPack, place-owned). deps: WaveService.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))

local WeaponWaveService = {}
local _wave = nil

local function templates()
	local folder = ServerStorage:FindFirstChild("WR_WaveWeapons")
	return folder and folder:GetChildren() or {}
end

local function hasTool(player, name): boolean
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp and bp:FindFirstChild(name) then return true end
	if player.Character and player.Character:FindFirstChild(name) then return true end
	return false
end

local function giveWeapons(player)
	local bp = player:FindFirstChildOfClass("Backpack")
	if not bp then return end
	for _, tmpl in ipairs(templates()) do
		if tmpl:IsA("Tool") and not hasTool(player, tmpl.Name) then
			local w = tmpl:Clone()
			w:SetAttribute("WR_WaveWeapon", true) -- znacznik do usuwania po fali
			w.Parent = bp
		end
	end
end

local function removeWeapons(player)
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("WR_WaveWeapon") then
					t:Destroy()
				end
			end
		end
	end
end

function WeaponWaveService.Init() end

function WeaponWaveService.Start()
	_wave = ServiceRegistry.get("WaveService")
	if _wave and _wave.WaveStarted then
		_wave.WaveStarted:Connect(function(player)
			giveWeapons(player)
		end)
	end
	if _wave and _wave.WaveEnded then
		_wave.WaveEnded:Connect(function(player)
			removeWeapons(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- sprzatanie nie potrzebne (gracz wychodzi), ale zostaw hak na przyszlosc
	end)

	if #templates() == 0 then
		warn("[WeaponWaveService] brak ServerStorage.WR_WaveWeapons — przenies tam bronie ze StarterPack")
	end
end

return WeaponWaveService
