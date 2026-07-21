--!strict
-- Content/Config/MutationConfig.luau — OSOBNY, niezalezny rzut po rolce glownej.
-- Algorytm (RollService): idz od najrzadszej (x8 -> x4 -> x2); pierwszy trafiony
-- rzut 1-in-chanceN wygrywa; brak trafienia -> bez mutacji.
local MutationConfig = {
	-- drabina do x128 (kaskada koniczyn); wyzszy mnoznik = rzadszy. Placeholdery (Olo retune).
	ladder = {
		{ id = "x2", mult = 2, chanceN = 25 }, -- 1 in 25
		{ id = "x4", mult = 4, chanceN = 100 }, -- 1 in 100
		{ id = "x8", mult = 8, chanceN = 500 }, -- 1 in 500
		{ id = "x16", mult = 16, chanceN = 2500 },
		{ id = "x32", mult = 32, chanceN = 12000 },
		{ id = "x64", mult = 64, chanceN = 60000 },
		{ id = "x128", mult = 128, chanceN = 300000 },
	},
}

return MutationConfig
