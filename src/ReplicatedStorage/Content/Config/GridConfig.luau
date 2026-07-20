--!strict
-- Content/Config/GridConfig.luau — wymiary siatki budowania + budzet kratek.
-- cellSize = 6 AUTHORED: zgodne z fizycznymi kaflami Tile 6x6 w placu (twarda regula).
-- PlotService przy starcie asertuje rozmiar realnego Tile == cellSize (warn przy rozjezdzie).
local GridConfig = {
	width = 9, -- kolumny (X)
	depth = 12, -- rzedy (Z)
	cellSize = 6, -- study na kratke (== fizyczny Tile)
	baseCellBudget = 40, -- bazowy budzet ZAJETYCH kratek (suma footprintow), nie liczba sztuk
}

return GridConfig
