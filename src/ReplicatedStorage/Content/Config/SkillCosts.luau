--!strict
-- Content/Config/SkillCosts.luau — BALANS CEN drzewa umiejetnosci.  <<< PLIK DLA OLO >>>
--
-- OLO: TU i TYLKO TU zmieniasz ceny umiejetnosci. Kazdy wpis NADPISUJE koszt z SkillTreeData.
--   coin = koszt w monetach, roll = koszt w rolkach (kostkach).
--   Wpisuj TYLKO jedna walute na wezel (>0), druga zostaw 0. (coin>0 -> kupno za monety; inaczej roll>0 -> za rolki.)
--   Zmieniasz WYLACZNIE liczby. NIE ruszaj id, NIE ruszaj struktury drzewa (to jest w SkillTreeData.luau).
--   Brak wpisu dla danego id = uzywany jest domyslny koszt z SkillTreeData (wiekszosc drzewa tak dziala).
--   Chcesz przecenic dowolny stary wezel? Dopisz mu tu linijke, np.  n70 = { coin = 200, roll = 0 },
--
-- Ponizej: MINIMALNE placeholdery dla nowej galezi bojowej (Player PRO). Dostroj do balansu gry.
return {
	-- ── Galaz bojowa (Player PRO) ──
	n105 = { coin = 250000,  roll = 0 },  -- Weapon Upgrade  (+10% dmg jednostek gracza)
	n106 = { coin = 1000000, roll = 0 },  -- Military Convoy (przejazd konwoju obija wrogow)
	n107 = { coin = 5000000, roll = 0 },  -- Nuke           (bomba atomowa, duzy AoE)
	n108 = { coin = 2500000, roll = 0 },  -- Air Raid       (nalot, bomba ~ciezki AoE)
	n109 = { coin = 100000,  roll = 0 },  -- Faster Shooting I   (+5% szybkostrzelnosci)
	n110 = { coin = 350000,  roll = 0 },  -- Faster Shooting II  (+10%)
	n111 = { coin = 900000,  roll = 0 },  -- Faster Shooting III (+30%)
}
