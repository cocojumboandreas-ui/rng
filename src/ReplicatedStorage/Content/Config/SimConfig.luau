--!strict
-- Content/Config/SimConfig.luau — parametry symulacji (KNOB bramki wydajnosci §10).
-- Bramka nie przechodzi -> najpierw kreci simHz (10->7), potem LOD/pule.
local SimConfig = {
	simHz = 10, -- tick symulacji na sekunde (jedna plaska petla dla wszystkich plotow)
	spawnStagger = 0.03, -- odstep pathT miedzy kolejnymi wrogami przy spawnie (formacja-kolumna)
	-- BLOKOWANIE: wrog nie przenika przez bloki/jednostki — staje przed przeszkoda i niszczy ja.
	blockAhead = 2.5, -- jak daleko przed wrogiem sprawdzamy przeszkode (study)
	blockRadius = 4.0, -- promien zajetosci postawionej jednostki/bloku (study; ~pol kafla=6/2+margines)
	playerShotDmg = 10, -- BALANS: ile HP zdejmuje 1 trafienie z broni FPS gracza (strzelanie w fali)
}

return SimConfig
