--!strict
-- Content/Config/MutationConfig.luau — OSOBNY, niezalezny rzut po rolce glownej.
-- Algorytm (RollService): idz od najrzadszej (x8 -> x4 -> x2); pierwszy trafiony
-- rzut 1-in-chanceN wygrywa; brak trafienia -> bez mutacji.
local MutationConfig = {
	-- KASKADA WSPINAJACA: wchodzisz od x2 w gore; `step` = szansa wejscia na TEN szczebel
	-- (skalowana statem mutChance). x2/x4 = 1.0 (zawsze), wyzsze % maleja. Zatrzymanie na
	-- pierwszym nietrafionym; final mnoznik = najwyzszy osiagniety. Placeholdery (Olo retune).
	ladder = {
		{ id = "x2", mult = 2, step = 1.0 }, -- zawsze
		{ id = "x4", mult = 4, step = 1.0 }, -- zawsze
		{ id = "x8", mult = 8, step = 0.12 }, -- wyzej RZADKO (na testy)
		{ id = "x16", mult = 16, step = 0.05 },
		{ id = "x32", mult = 32, step = 0.02 },
		{ id = "x64", mult = 64, step = 0.008 },
		{ id = "x128", mult = 128, step = 0.003 },
	},
}

return MutationConfig
