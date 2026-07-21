--!strict
-- Content/Config/IndexConfig.luau — kolekcja jednostek: progi %ukonczenia -> permanentny bonus luck.
-- total NIE hardcodowany: liczba UNIKALNYCH TYPOW jednostek z UnitsConfig (liczone w IndexService).
-- Indeks liczy TYPY (unitId), NIE mutacje. Wartosci = placeholdery (Olo retune).
-- Semantyka bonusu: NAJWYZSZY osiagniety prog (highest-reached), nie suma progow.
local IndexConfig = {
	luckThresholds = {
		{ pct = 25, luck = 0.5 },
		{ pct = 50, luck = 1.0 },
		{ pct = 100, luck = 2.0 },
	},
}

return IndexConfig
