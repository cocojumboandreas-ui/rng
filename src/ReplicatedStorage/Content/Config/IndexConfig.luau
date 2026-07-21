--!strict
-- Content/Config/IndexConfig.luau — kolekcja: 4 KATEGORIE + progi %ukonczenia -> permanentny bonus luck.
-- ETAP 2: indeks grupuje kolekcje w 4 kategorie i liczy wpisy PER WARIANT.
--   3 kategorie jednostek (kind="unit") = te same TYPY z UnitsConfig, ale osobno per wariant
--     (variant musi zgadzac sie z VariantConfig.variants: regular/shiny/galaxy). total kazdej = #typow (9).
--   Wrogowie (kind="enemy") = zakladka istnieje, ale STUB w tym etapie (odkrywanie = ETAP 5).
--     total = #WaveConfig.enemyTypes (liczone w IndexService, nie hardcode).
-- total NIE hardcodowany: IndexService liczy z UnitsConfig / WaveConfig.enemyTypes.
-- Semantyka bonusu: NAJWYZSZY osiagniety prog (highest-reached) z LACZNEGO %ukonczenia. Wartosci = placeholdery.
local IndexConfig = {
	-- kolejnosc = kolejnosc zakladek w UI
	categories = {
		{ id = "regular", label = "Regularny", kind = "unit", variant = "regular" },
		{ id = "shiny", label = "Blyszczacy", kind = "unit", variant = "shiny" },
		{ id = "galaxy", label = "Galaktyka", kind = "unit", variant = "galaxy" },
		{ id = "enemies", label = "Wrogowie", kind = "enemy" }, -- STUB (etap 5)
	},
	luckThresholds = {
		{ pct = 25, luck = 0.5 },
		{ pct = 50, luck = 1.0 },
		{ pct = 100, luck = 2.0 },
	},
}

return IndexConfig
