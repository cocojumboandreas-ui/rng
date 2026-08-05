--!strict
-- Content/Config/SkillEffectConfig.luau — BALANS DZIALANIA galezi bojowej (Faza 2).  <<< PLIK DLA OLO >>>
--
-- CENY sa w SkillCosts.luau. TU sa PARAMETRY EFEKTU: dmg / promien / szansa / cooldown. Zmieniasz TYLKO liczby.
-- (Prosty, plaski dmg — dostroj do HP wrogow na falach, na ktorych ma to jeszcze cos robic.)
return {
	-- ── Explosive Ammo (pasywne) ──  n78 = baza; n95-98 mnoza szanse (bierzemy NAJWYZSZY posiadany tier).
	-- Przy trafieniu wiezy jest `chance` na wybuch: AoE `splashFrac` * dmg wiezy w promieniu `splashRadius`.
	explosive = {
		baseChance = 0.10, -- szansa na splash gdy masz Explosive Ammo (n78)
		tierMult = { n78 = 1, n95 = 1.5, n96 = 2, n97 = 3, n98 = 5 }, -- najwyzszy posiadany tier x baseChance
		splashRadius = 9, -- promien splash [study]
		splashFrac = 0.6, -- ile % dmg wiezy dostaja sasiedzi w promieniu
	},

	-- ── Strike'i (auto co fale, na cooldownie) ──  konwoj / nalot / nuke.
	-- Po odblokowaniu wezla, w trakcie fali, co `cooldown` sekund uderza AoE `dmg` w promieniu `radius`
	-- w skupisko wrogow. node = id wezla w drzewie ktory to odblokowuje.
	strikes = {
		convoy = { node = "n106", cooldown = 22, dmg = 60, radius = 14 }, -- Military Convoy
		airRaid = { node = "n108", cooldown = 32, dmg = 180, radius = 16 }, -- Air Raid (nalot)
		nuke = { node = "n107", cooldown = 95, dmg = 900, radius = 42 }, -- Nuke (bomba atomowa)
	},

	-- Bonus / Bonus Frenzy: szansa na ULEPSZENIE wyrolowanego itemu o 1 tier w gore (rzadszy). Delty kumulatywne.
	bonus = {
		tierUpChance = { n39 = 0.05, n40 = 0.05, n43 = 0.05, n44 = 0.10, n45 = 0.10, n46 = 0.25 }, -- suma do 60%
	},

	-- Offline Rolls: mnoznik zarobkow offline (MONETY i ROLKI). n3 (Offline Progression) ODBLOKOWUJE rolki offline.
	offline = {
		mult = { n22 = 0.15, n23 = 0.20, n27 = 0.15, n28 = 0.25, n29 = 0.25, n30 = 0.50 }, -- suma do +150%
		unlockNode = "n3",
	},

	-- Gold/Diamond/Rainbow Rolls: OSOBNE liczniki per typ. Co N rolek (min N wsrod POSIADANYCH wezlow typu)
	-- jedna rolka dostaje x{mult} luck. mniejsze N = czesciej. Typy niezalezne (gdy kilka trafi te sama rolke -> najwyzszy mult).
	specialRolls = {
		gold = { mult = 3, everyByNode = { n4 = 12, n6 = 11, n7 = 10, n9 = 8, n10 = 6 } },
		diamond = { mult = 8, everyByNode = { n8 = 30, n11 = 28, n12 = 25, n13 = 21, n14 = 18 } },
		rainbow = { mult = 40, everyByNode = { n15 = 100, n16 = 90, n17 = 80, n20 = 75, n21 = 45, n104 = 30 } },
	},

	-- Automatic Roll (n2): gdy posiadany -> pasywna regeneracja rolek (regenPerSec) + auto-rolka co rollSpeed,
	-- ktora zuzywa `cost` rolek. regenPerSec >= 1/rollSpeed -> rolki nigdy nie schodza do 0 (regeneracja bez konca).
	autoRoll = { node = "n2", regenPerSec = 0.35, cost = 1 },
}
