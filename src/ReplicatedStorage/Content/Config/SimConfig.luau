--!strict
-- Content/Config/SimConfig.luau — parametry symulacji (KNOB bramki wydajnosci §10).
-- Bramka nie przechodzi -> najpierw kreci simHz (10->7), potem LOD/pule.
local SimConfig = {
	simHz = 10, -- tick symulacji na sekunde (jedna plaska petla dla wszystkich plotow)
	spawnStagger = 0.03, -- odstep pathT miedzy kolejnymi wrogami przy spawnie (formacja-kolumna)
}

return SimConfig
