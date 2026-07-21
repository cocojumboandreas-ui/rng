--!strict
-- Content/Config/VariantConfig.luau — TRZECIA os rolla: WARIANT (finish kolekcjonerski)
-- obok bazy (1 in N) i mutacji (x2/x4/x8). v1: TYLKO wizual + wartosc kolekcjonerska — ZERO
-- wplywu na staty (staty jednostki dalej z mutacji i przyszlego poziomu indeksu).
-- Algorytm jak drabina mutacji: idz OD NAJRZADSZEGO (galaxy -> shiny); pierwszy trafiony
-- rzut 1-in-chanceN wygrywa; brak trafienia -> regular (fallback).
-- Rzut skalowany statem variantLuck (hook pod przyszle gamepassy "5x shiny/galaxy chance").
local VariantConfig = {
	variants = { "regular", "shiny", "galaxy" }, -- pelna lista (pospolity -> rzadki)
	-- OD NAJRZADSZEGO (iteruj forward). Placeholdery (Olo retune).
	ladder = {
		{ id = "galaxy", chanceN = 1000 }, -- 1 in 1000
		{ id = "shiny", chanceN = 50 }, -- 1 in 50
	},
	fallback = "regular",
}

return VariantConfig
