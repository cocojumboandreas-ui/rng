--!strict
-- Content/Config/SimConfig.luau — parametry symulacji (KNOB bramki wydajnosci §10).
-- Bramka nie przechodzi -> najpierw kreci simHz (10->7), potem LOD/pule.
local SimConfig = {
	simHz = 10, -- tick symulacji na sekunde (jedna plaska petla dla wszystkich plotow)
	spawnStagger = 0.03, -- odstep pathT miedzy kolejnymi wrogami przy spawnie (formacja-kolumna)
	-- BLOKOWANIE: wrog nie przenika przez bloki/jednostki — staje ~1 stud PRZED przeszkoda na swoim pasie i strzela.
	blockStopDist = 6.5, -- dystans SRODEK-SRODEK, przy ktorym wrog staje przed placementem (blok ~3 + wrog ~2.4 + ~1 stud luki)
	blockLaneHalf = 3.6, -- max boczne odchylenie placementu od pasa wroga, by liczyl sie jako przeszkoda (~pol kafla 6/2 + margines)
	blockAhead = 2.5, -- (legacy, nieuzywane po zmianie na standoff) — zostaje dla zgodnosci configu
	blockRadius = 4.0, -- (legacy, jw.)
	playerShotDmg = 10, -- BALANS: fallback dmg/strzal broni FPS gracza (gdy brak wpisu per-bron ponizej)
	playerWeaponDmg = { Pistol = 10, AR = 8, Shotgun = 24, Sniper = 60 }, -- BALANS: dmg/strzal per BRON (nazwa Tool z WR_WaveWeapons); brak wpisu -> playerShotDmg
	headshotMult = 1.5, -- BALANS: mnoznik obrazen za trafienie w GLOWE (HEAD SHOT). 1.0 = tylko wizual, bez bonusu.
	unitRangeMult = 1.0, -- BALANS: globalny mnoznik zasiegu WSZYSTKICH jednostek gracza. 1.0 = pelny zasieg z UnitsConfig (bylo 0.6=-40%, dlawil ile wrogow wieza angazuje naraz).
	defMinChipFrac = 0.2, -- DEF blokuje max (1-frac)=80% obrazen. Wrog ZAWSZE chipuje blok >=frac*atkDmg -> zaden
	-- blok NIE jest niezniszczalny, droga ZAWSZE sie w koncu utoruje (koniec deadlocka: def>=atkDmg => 0 dmg => wrog wiecznie utkniety).
}

return SimConfig
