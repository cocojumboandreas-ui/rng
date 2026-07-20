--!strict
-- Content/Config/MutationConfig.luau — OSOBNY, niezalezny rzut po rolce glownej.
-- Algorytm (RollService): idz od najrzadszej (x8 -> x4 -> x2); pierwszy trafiony
-- rzut 1-in-chanceN wygrywa; brak trafienia -> bez mutacji.
local MutationConfig = {
	ladder = {
		{ id = "x2", mult = 2, chanceN = 25 }, -- 1 in 25
		{ id = "x4", mult = 4, chanceN = 100 }, -- 1 in 100
		{ id = "x8", mult = 8, chanceN = 500 }, -- 1 in 500
	},
}

return MutationConfig
