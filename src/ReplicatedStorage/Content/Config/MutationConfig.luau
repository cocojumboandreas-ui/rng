--!strict
-- Content/Config/MutationConfig.luau — OSOBNY, niezalezny rzut po rolce glownej.
-- Algorytm (RollService): idz od najrzadszej (x8 -> x4 -> x2); pierwszy trafiony
-- rzut 1-in-chanceN wygrywa; brak trafienia -> bez mutacji.
local MutationConfig = {
	-- KASKADA WSPINAJACA: wchodzisz od x2 w gore; `step` = szansa wejscia na TEN szczebel
	-- (skalowana statem mutChance). x2/x4 = 1.0 (zawsze), wyzsze % maleja. Zatrzymanie na
	-- pierwszym nietrafionym; final mnoznik = najwyzszy osiagniety. Placeholdery (Olo retune).
	ladder = {
		{ id = "x2", mult = 2, step = 0.385 }, -- ~38.5% na JAKAKOLWIEK koniczyne (x mutChance); NIE zawsze (bylo 1.0)
		{ id = "x4", mult = 4, step = 0.5 }, -- gdy zlapano x2: 50% na x4 (dalej wg ponizszych)
		{ id = "x8", mult = 8, step = 0.6 }, -- na testy 60%
		{ id = "x16", mult = 16, step = 0.05 },
		{ id = "x32", mult = 32, step = 0.02 },
		{ id = "x64", mult = 64, step = 0.008 },
		{ id = "x128", mult = 128, step = 0.003 },
	},
	-- SUFIT DRABINY: domyslnie koniczyny wchodza max do x8 (index 3). Skille x16/x32/x64 podnosza sufit.
	-- baseCloverTier = index w `ladder` (1=x2,2=x4,3=x8,4=x16,5=x32,6=x64,7=x128). tierUnlock: id wezla drzewa -> index.
	baseCloverTier = 3,
	tierUnlock = { n53 = 4, n63 = 5, n64 = 6 }, -- x16 Clover / x32 Clover / x64 Clover
}

return MutationConfig
