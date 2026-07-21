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
local B = Enums.UnitKind.Block

local Units = {
	-- hp = wytrzymalosc jednostki (faza 5: wrogowie zadaja dmg, jednostka ginie przy 0). Tarcze/tanki = duzo hp.
	noob_soldier = {
		kind = W, rarityN = 3, footprint = { w = 1, d = 1 }, hp = 80,
		combat = { dmg = 3, fireRate = 1.0, range = 10 },
		model = "Noob Soldier", displayName = "Rekrut",
	},
	soldier = {
		kind = W, rarityN = 8, footprint = { w = 1, d = 1 }, hp = 140,
		combat = { dmg = 6, fireRate = 1.2, range = 14 }, -- karabin: ciut lepszy od noob
		model = "Soldier", displayName = "Zolnierz",
	},
	sniper = {
		kind = W, rarityN = 15, footprint = { w = 1, d = 1 }, hp = 120,
		combat = { dmg = 16, fireRate = 0.4, range = 30 }, -- duzy zasieg/dmg, wolny
		model = "Sniper", displayName = "Snajper",
	},
	swat = {
		kind = W, rarityN = 30, footprint = { w = 1, d = 1 }, hp = 500, -- tarcza = duzo HP (tank)
		combat = { dmg = 8, fireRate = 1.4, range = 16 }, -- rifle + tarcza
		model = "SWAT", displayName = "SWAT",
	},
	rocket_soldier = {
		kind = W, rarityN = 60, footprint = { w = 1, d = 1 }, hp = 200,
		combat = { dmg = 30, fireRate = 0.5, range = 28 }, -- RPG: zasieg jak sniper, duzy dmg, wybuch
		model = "Rocket Soldier", displayName = "Rakietowiec",
	},
	flamethrower = {
		kind = W, rarityN = 100, footprint = { w = 1, d = 1 }, hp = 400,
		combat = { dmg = 8, fireRate = 4.0, range = 10 }, -- miotacz: krotki zasieg, szybki DPS
		model = "Flamethrower", displayName = "Miotacz ognia",
	},
	tank_soldier = {
		kind = W, rarityN = 150, footprint = { w = 1, d = 1 }, hp = 900, -- Big Shield = bardzo tanky
		combat = { dmg = 5, fireRate = 6.0, range = 16 }, -- minigun: malo dmg/pocisk, bardzo szybko
		model = "Tank Soldier", displayName = "Ciezki piechur",
	},
	jeep = {
		kind = W, rarityN = 300, footprint = { w = 2, d = 2 }, hp = 700,
		combat = { dmg = 8, fireRate = 1.5, range = 14 }, -- kierowca Noob strzela z pistoletu; duzo HP
		model = "Jeep", displayName = "Jeep",
		driver = "Noob Soldier", -- renderer doklada kierowce (kompozycja modelu)
	},
	tank = {
		kind = W, rarityN = 1500, footprint = { w = 2, d = 2 }, hp = 1500, -- najwiecej HP
		combat = { dmg = 85, fireRate = 0.6, range = 24 }, -- dzialo glowne: najwiecej HP, ogromny dmg
		model = "Tank", displayName = "Czolg",
	},
	helicopter = {
		kind = W, rarityN = 800, footprint = { w = 2, d = 2 }, hp = 900,
		combat = { dmg = 24, fireRate = 5.0, range = 34 }, -- 2 miniguny, najwiekszy zasieg, lata (hover)
		model = "Helicopter", displayName = "Helikopter",
	},
	jet = {
		kind = W, rarityN = 2000, footprint = { w = 2, d = 2 }, hp = 700, -- HP jak jeep
		combat = { dmg = 100, fireRate = 1.2, range = 40 }, -- lasery, ogromny dmg, HP jak jeep, lata
		model = "Jet", displayName = "Jet",
	},

	-- ── TEST CONTENT (placeholder, nazwy do podmiany; ids/klucze zostaja EN) ──────
	-- Modele budowane w RUNTIME przez UnitModelFactory (brak `model` -> placeholder z kodu).
	-- BLOKI: kind=Block, footprint 1x1, brak combat (pasywne), hp w configu (StatProfile-spojne).
	test_block_wood = {
		kind = B, category = "block", rarityN = 5, footprint = { w = 1, d = 1 },
		hp = 500, displayName = "Blok drewna",
	},
	test_block_stone = {
		kind = B, category = "block", rarityN = 15, footprint = { w = 1, d = 1 },
		hp = 1200, displayName = "Blok kamienia",
	},
	test_block_iron = {
		kind = B, category = "block", rarityN = 40, footprint = { w = 1, d = 1 },
		hp = 3000, displayName = "Blok zelaza",
	},
	test_block_rusty = {
		kind = B, category = "block", rarityN = 150, footprint = { w = 1, d = 1 },
		hp = 6000, displayName = "Blok zardzewialy",
	},
	-- BRONIE: kind=Weapon, footprint 1x1, base combat czytane przez StatProfile (dmg/fireRate/range Mult).
	test_weapon_pistol = {
		kind = W, category = "weapon", rarityN = 10, footprint = { w = 1, d = 1 },
		combat = { dmg = 8, fireRate = 2.0, range = 35 },
		displayName = "Pistolet (test)",
	},
	test_weapon_rifle = {
		kind = W, category = "weapon", rarityN = 60, footprint = { w = 1, d = 1 },
		combat = { dmg = 14, fireRate = 3.0, range = 45 },
		displayName = "Karabin (test)",
	},
	test_weapon_cannon = {
		kind = W, category = "weapon", rarityN = 300, footprint = { w = 1, d = 1 },
		combat = { dmg = 55, fireRate = 0.7, range = 60 },
		displayName = "Dzialko (test)",
	},
	test_weapon_launcher = {
		kind = W, category = "weapon", rarityN = 1500, footprint = { w = 1, d = 1 },
		combat = { dmg = 140, fireRate = 0.4, range = 70 },
		displayName = "Wyrzutnia (test)",
	},
}

-- Jet / Helicopter: modele istnieja w Assets.Units, ale NIE placeable w v1 (poza roster).

return Units
