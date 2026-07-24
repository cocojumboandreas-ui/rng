--!nonstrict
-- ServerScriptService/Services/WeaponWaveService.luau
-- Bronie FPS gracza TYLKO gdy: (a) leci fala ORAZ (b) gracz wlaczyl tryb strzelania (klawisz U -> Net.SetShootMode).
-- Poza tym brak broni -> WeaponsSystem/ShoulderCamera nieaktywne -> normalna kamera 3-os + wolna mysz.
-- Szablony broni: ServerStorage.WR_WaveWeapons (place-owned). deps: WaveService (gate fazy + cleanup na WaveEnded).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local Enums = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Enums"))

local WeaponWaveService = {}
local _wave = nil

local function templates()
	local folder = ServerStorage:FindFirstChild("WR_WaveWeapons")
	return folder and folder:GetChildren() or {}
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

local function giveWeapons(player)
	local bp = player:FindFirstChildOfClass("Backpack")
	if not bp then return end
	for _, tmpl in ipairs(templates()) do
		if tmpl:IsA("Tool") then
			local w = tmpl:Clone()
			w:SetAttribute("WR_WaveWeapon", true) -- znacznik do usuwania
			w.Parent = bp
		end
	end
end

local function waveActive(player): boolean
	return _wave and _wave.GetPhase and _wave.GetPhase(player) == Enums.RunPhase.WaveActive or false
end

function WeaponWaveService.Init() end

function WeaponWaveService.Start()
	_wave = ServiceRegistry.get("WaveService")

	Net.get("SetShootMode").OnServerEvent:Connect(function(player, on)
		removeWeapons(player) -- zawsze najpierw czysto (brak duplikatow)
		if on == true and waveActive(player) then
			giveWeapons(player)
		end
	end)

	-- koniec fali / runu -> zabierz bronie (gdyby gracz zostal w trybie strzelania).
	-- Opoznienie: daj klientowi chwile na CZYSTY unequip (kit chowa celownik + wraca animacja)
	-- ZANIM zniszczymy narzedzia. Bez tego Destroy wyprzedza unequip -> celownik/kamera zwisaja.
	if _wave and _wave.WaveEnded then
		_wave.WaveEnded:Connect(function(player)
			task.delay(0.4, function()
				if player and player.Parent then
					removeWeapons(player)
				end
			end)
		end)
	end

	if #templates() == 0 then
		warn("[WeaponWaveService] brak ServerStorage.WR_WaveWeapons — przenies tam bronie ze StarterPack")
	end
end

return WeaponWaveService
