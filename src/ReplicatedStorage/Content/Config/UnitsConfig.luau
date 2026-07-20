--!strict
-- Content/Config/UnitsConfig.luau — definicje jednostek (TYPY, nie egzemplarze).
-- Drabina rzadkosci kalibrowana z Build a Base RNG: 1in3 -> 1in1500.
-- Footprinty AUTHORED: piechota 1x1, pojazdy 2x2. Jet/Helicopter NIE placeable w v1 (pominiete).
-- Dublet z placu: uzywamy "Flamethrower" (pelny model); "FlameThrower" (pusty 5x1x0) pominiety.
-- ODSTEPSTWO od §4: zamiast modelId=assetId uzywamy `model` = nazwa dziecka w
-- ReplicatedStorage.Assets.Units (modele sklonowane w MAP PREP; Build klonuje po tej nazwie).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Enums = require(Shared:WaitForChild("Enums"))

local W = Enums.UnitKind.Weapon

local Units = {
	noob_soldier = {
		kind = W, rarityN = 3, footprint = { w = 1, d = 1 },
		combat = { dmg = 3, fireRate = 1.0, range = 10 },
		model = "Noob Soldier", displayName = "Rekrut",
	},
	soldier = {
		kind = W, rarityN = 8, footprint = { w = 1, d = 1 },
		combat = { dmg = 5, fireRate = 1.0, range = 12 },
		model = "Soldier", displayName = "Zolnierz",
	},
	sniper = {
		kind = W, rarityN = 15, footprint = { w = 1, d = 1 },
		combat = { dmg = 14, fireRate = 0.4, range = 26 },
		model = "Sniper", displayName = "Snajper",
	},
	swat = {
		kind = W, rarityN = 30, footprint = { w = 1, d = 1 },
		combat = { dmg = 8, fireRate = 1.4, range = 14 },
		model = "SWAT", displayName = "SWAT",
	},
	rocket_soldier = {
		kind = W, rarityN = 60, footprint = { w = 1, d = 1 },
		combat = { dmg = 22, fireRate = 0.5, range = 18 },
		model = "Rocket Soldier", displayName = "Rakietowiec",
	},
	flamethrower = {
		kind = W, rarityN = 100, footprint = { w = 1, d = 1 },
		combat = { dmg = 10, fireRate = 2.0, range = 8 },
		model = "Flamethrower", displayName = "Miotacz ognia",
	},
	tank_soldier = {
		kind = W, rarityN = 150, footprint = { w = 1, d = 1 },
		combat = { dmg = 18, fireRate = 0.9, range = 14 },
		model = "Tank Soldier", displayName = "Ciezki piechur",
	},
	jeep = {
		kind = W, rarityN = 300, footprint = { w = 2, d = 2 },
		combat = { dmg = 16, fireRate = 1.6, range = 16 },
		model = "Jeep", displayName = "Jeep",
	},
	tank = {
		kind = W, rarityN = 1500, footprint = { w = 2, d = 2 },
		combat = { dmg = 60, fireRate = 0.6, range = 22 },
		model = "Tank", displayName = "Czolg",
	},
}

-- Jet / Helicopter: modele istnieja w Assets.Units, ale NIE placeable w v1 (poza roster).

return Units
