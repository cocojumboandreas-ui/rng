--!strict
-- Content/Config/UnitsConfig.luau — definicje jednostek (TYPY, nie egzemplarze).
-- Drabina rzadkosci kalibrowana z Build a Base RNG: 1in3 -> 1in2000.
-- Footprinty AUTHORED: piechota 1x1, pojazdy 2x2 (jeep/tank/heli/jet). (Uwaga: wczesniejszy komentarz mowil,
-- ze Jet/Heli NIE placeable w v1 — NIEAKTUALNE: sa pelnoprawnymi weaponami w rosterze ponizej.)
-- Dublet z placu: uzywamy "Flamethrower" (pelny model); "FlameThrower" (pusty 5x1x0) pominiety.
-- ODSTEPSTWO od §4: zamiast modelId=assetId uzywamy `model` = nazwa dziecka w
-- ReplicatedStorage.Assets.Units (modele sklonowane w MAP PREP; Build klonuje po tej nazwie).
--
-- ⚠ BALANS DPS (re-tune 2026-07): base DPS = dmg*fireRate jest teraz MONOTONICZNY z rzadkoscia
-- (rzadsze = mocniejsze). fireRate ZACHOWANE (archetyp: sniper wolny-mocny, minigun szybki-slaby,
-- czolg/jet burst), zmieniany glownie `dmg`. Drabina base DPS:
--   noob 4  <  zolnierz 9.6  <  sniper 14  <  swat 18  <  rakieta 28  <  miotacz 40  <
--   ciezki 54  <  jeep 81  <  heli 150  <  czolg 258  <  jet 342.
-- Lewelowanie (Etap 3) MNOZY na wierzchu (base*1.10^lvl). Zasieg globalnie x SimConfig.unitRangeMult (teraz 1.0).
-- HP/def/zasieg NIE zmienione — to osobne pokretla; tu tylko DPS.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Enums = require(Shared:WaitForChild("Enums"))

local W = Enums.UnitKind.Weapon
local B = Enums.UnitKind.Block

local Units = {
	-- hp = wytrzymalosc jednostki (faza 5: wrogowie zadaja dmg, jednostka ginie przy 0). Tarcze/tanki = duzo hp.
	noob_soldier = {
		kind = W, rarityN = 3, footprint = { w = 1, d = 1 }, hp = 80,
		combat = { dmg = 4, fireRate = 1.0, range = 10 }, -- DPS 4
		model = "Noob Soldier", displayName = "Recruit",
	},
	soldier = {
		kind = W, rarityN = 8, footprint = { w = 1, d = 1 }, hp = 140,
		combat = { dmg = 8, fireRate = 1.2, range = 14 }, -- karabin: DPS 9.6
		model = "Soldier", displayName = "Soldier",
	},
	sniper = {
		kind = W, rarityN = 15, footprint = { w = 1, d = 1 }, hp = 120,
		combat = { dmg = 35, fireRate = 0.4, range = 30 }, -- duzy zasieg/dmg, wolny: DPS 14
		model = "Sniper", displayName = "Sniper",
	},
	swat = {
		kind = W, rarityN = 30, footprint = { w = 1, d = 1 }, hp = 500, def = 6, -- tarcza = duzo HP (tank) + DEF
		combat = { dmg = 13, fireRate = 1.4, range = 16 }, -- rifle + tarcza: DPS 18.2
		model = "SWAT", displayName = "SWAT",
	},
	rocket_soldier = {
		kind = W, rarityN = 60, footprint = { w = 1, d = 1 }, hp = 200,
		combat = { dmg = 56, fireRate = 0.5, range = 28 }, -- RPG: zasieg jak sniper, duzy dmg, wybuch: DPS 28
		model = "Rocket Soldier", displayName = "Rocketeer",
	},
	flamethrower = {
		kind = W, rarityN = 100, footprint = { w = 1, d = 1 }, hp = 400,
		combat = { dmg = 10, fireRate = 4.0, range = 10 }, -- miotacz: krotki zasieg, szybki DPS: DPS 40
		model = "Flamethrower", displayName = "Flamethrower",
	},
	tank_soldier = {
		kind = W, rarityN = 150, footprint = { w = 1, d = 1 }, hp = 900, def = 12, -- Big Shield = bardzo tanky + DEF
		combat = { dmg = 9, fireRate = 6.0, range = 16 }, -- minigun: malo dmg/pocisk, bardzo szybko: DPS 54
		model = "Tank Soldier", displayName = "Heavy Trooper",
	},
	jeep = {
		kind = W, rarityN = 300, footprint = { w = 2, d = 2 }, hp = 700, def = 8,
		combat = { dmg = 54, fireRate = 1.5, range = 14 }, -- kierowca strzela; duzo HP: DPS 81
		model = "Jeep", displayName = "Jeep",
		driver = "Noob Soldier", -- renderer doklada kierowce (kompozycja modelu)
	},
	tank = {
		kind = W, rarityN = 1500, footprint = { w = 2, d = 2 }, hp = 1500, def = 22, -- najwiecej HP + pancerz
		combat = { dmg = 430, fireRate = 0.6, range = 24 }, -- dzialo glowne: ogromny burst: DPS 258
		model = "Tank", displayName = "Tank",
	},
	helicopter = {
		kind = W, rarityN = 800, footprint = { w = 2, d = 2 }, hp = 900, def = 6,
		combat = { dmg = 30, fireRate = 5.0, range = 34 }, -- 2 miniguny, najwiekszy zasieg, lata: DPS 150
		model = "Helicopter", displayName = "Helicopter",
	},
	jet = {
		kind = W, rarityN = 2000, footprint = { w = 2, d = 2 }, hp = 700, -- HP jak jeep
		combat = { dmg = 285, fireRate = 1.2, range = 40 }, -- lasery, ogromny dmg, lata: DPS 342
		model = "Jet", displayName = "Jet",
	},

	-- ── HEAVY WEAPONS (mesh/items, upload 2026-08, grupa 664399796) ────────────────
	-- 8 nowych meshy w Assets.Units. rollowalne + w Indeksie + stawialne. DPS na drabinie (rzadsze=mocniejsze).
	-- special = zaczep dla proceduralnego zachowania (sekwencyjne rakiety / obrot+naboje / dron); dopoki brak
	-- handlera, dzialaja jak zwykla wieza przez CombatService (combat.dmg*fireRate). AoE/dron = kolejny etap.
	mg_nest_a = {
		kind = W, rarityN = 250, footprint = { w = 1, d = 1 }, hp = 350,
		combat = { dmg = 8, fireRate = 8.0, range = 28 }, -- KM na trojnogu, szybkie naboje, daleki zasieg: DPS 64
		model = "MG Nest A", displayName = "MG Nest",
		special = "mg",
	},
	rocket_launcher_x2 = {
		kind = W, rarityN = 500, footprint = { w = 1, d = 1 }, hp = 300,
		combat = { dmg = 110, fireRate = 1.0, range = 44 }, -- wyrzutnia 2-tub, AoE daleki zasieg: DPS 110
		model = "Rocket Launcher x2", displayName = "Rocket Launcher II",
		special = "launcher", tubes = 2, aoe = 12,
	},
	mg_nest_b = {
		kind = W, rarityN = 600, footprint = { w = 1, d = 1 }, hp = 450,
		combat = { dmg = 11, fireRate = 10.0, range = 30 }, -- ciezszy KM, daleki zasieg: DPS 110
		model = "MG Nest B", displayName = "Heavy MG Nest",
		special = "mg",
	},
	minigun_turret = {
		kind = W, rarityN = 1000, footprint = { w = 1, d = 1 }, hp = 600, def = 6,
		combat = { dmg = 16, fireRate = 12.0, range = 34 }, -- minigan obrotowy, daleki zasieg: DPS 192
		model = "Minigun Turret", displayName = "Minigun Turret",
		special = "minigun",
	},
	rocket_launcher_x4 = {
		kind = W, rarityN = 1200, footprint = { w = 1, d = 1 }, hp = 400,
		combat = { dmg = 230, fireRate = 1.0, range = 46 }, -- wyrzutnia 4-tub, 1 salwa/s (4 rakiety AoE), daleki zasieg: DPS 230
		model = "Rocket Launcher x4", displayName = "Rocket Launcher IV",
		special = "launcher", tubes = 4, aoe = 14,
	},
	dual_minigun = {
		kind = W, rarityN = 2500, footprint = { w = 1, d = 1 }, hp = 800, def = 10,
		combat = { dmg = 24, fireRate = 16.0, range = 38 }, -- podwojny minigan, daleki zasieg: DPS 384
		model = "Dual Minigun", displayName = "Dual Minigun",
		special = "minigun",
	},
	rocket_launcher_x6 = {
		kind = W, rarityN = 3500, footprint = { w = 1, d = 1 }, hp = 500,
		combat = { dmg = 468, fireRate = 1.0, range = 50 }, -- wyrzutnia 6-tub, 1 salwa/s (6 rakiet AoE), daleki zasieg: DPS 468
		model = "Rocket Launcher x6", displayName = "Rocket Launcher VI",
		special = "launcher", tubes = 6, aoe = 16,
	},
	drone_base = {
		kind = W, rarityN = 5000, footprint = { w = 2, d = 2 }, hp = 600, -- baza = 2x2 pola (dron startuje/wraca)
		combat = { dmg = 200, fireRate = 1.0, range = 55 }, -- dron: parabola z gory, AoE bardzo daleki zasieg: DPS 200
		model = "Drone Base", displayName = "Drone Base",
		special = "drone", aoe = 16,
	},

	-- ── TEST CONTENT (placeholder, nazwy do podmiany; ids/klucze zostaja EN) ──────
	-- Modele budowane w RUNTIME przez UnitModelFactory (brak `model` -> placeholder z kodu).
	-- BLOKI: kind=Block, footprint 1x1, brak combat (PASYWNE - NIE strzelaja, NIE zadaja obrazen wrogom),
	-- hp w configu. def = pancerz bloku: obrazenia wroga = max(0, atkDmg - def). Obrona W PELNI chroni:
	-- gdy def >= atkDmg wroga -> blok dostaje 0 (nie traci HP). Slaby wrog nie ruszy dobrego bloku;
	-- dopiero silniejszy (wyzszy tier / pozniejsza fala) przebija. Lepszy material = wyzszy def i hp.
	test_block_wood = {
		kind = B, category = "block", rarityN = 5, footprint = { w = 1, d = 1 },
		hp = 500, def = 10, displayName = "Wood Block",
	},
	test_block_stone = {
		kind = B, category = "block", rarityN = 15, footprint = { w = 1, d = 1 },
		hp = 1200, def = 22, displayName = "Stone Block",
	},
	test_block_iron = {
		kind = B, category = "block", rarityN = 40, footprint = { w = 1, d = 1 },
		hp = 3000, def = 45, displayName = "Iron Block",
	},
	test_block_rusty = {
		kind = B, category = "block", rarityN = 150, footprint = { w = 1, d = 1 },
		hp = 6000, def = 80, displayName = "Rusty Block",
	},
	-- BRONIE TEST: kind=Weapon, footprint 1x1. DPS dostrojone do drabiny (monotoniczne wg rarityN).
	test_weapon_pistol = {
		kind = W, category = "weapon", rarityN = 10, footprint = { w = 1, d = 1 },
		combat = { dmg = 6, fireRate = 2.0, range = 35 }, -- DPS 12
		displayName = "Pistol (test)",
	},
	test_weapon_rifle = {
		kind = W, category = "weapon", rarityN = 60, footprint = { w = 1, d = 1 },
		combat = { dmg = 9, fireRate = 3.0, range = 45 }, -- DPS 27
		displayName = "Rifle (test)",
	},
	test_weapon_cannon = {
		kind = W, category = "weapon", rarityN = 300, footprint = { w = 1, d = 1 },
		combat = { dmg = 114, fireRate = 0.7, range = 60 }, -- DPS 79.8
		displayName = "Cannon (test)",
	},
	test_weapon_launcher = {
		kind = W, category = "weapon", rarityN = 1500, footprint = { w = 1, d = 1 },
		combat = { dmg = 645, fireRate = 0.4, range = 70 }, -- DPS 258
		displayName = "Launcher (test)",
	},
}

-- Jet / Helicopter: modele istnieja w Assets.Units, ale NIE placeable w v1 (poza roster).

return Units
