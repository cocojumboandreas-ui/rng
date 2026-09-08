--!strict
-- Content/Config/LaneConfig.luau — kolumny wejscia wrogow do rdzenia.
-- STALE przez cala gre: ZERO skalowania z numerem fali, zero rosnacego rozrzutu.
-- Srodek (4,5,6) dominuje, flanki (3,7) rzadko. Kolumny 1,2,8,9 nigdy nie sa celem.
-- Wagi = placeholder do dostrojenia (BALANCE.md), stosunek srodek:flanki ustawia Andreas.
local LaneConfig = {
	columns = { 3, 4, 5, 6, 7 },
	-- splaszczone: boki (3,7) realnie uzywane -> wrogowie losowo rzucaja sie w lewo/prawo po 5 srodkowych slotach
	-- (serwer losuje kolumne per wrog RNG, wysyla do klienta -> rozne strony bez sekwencji). Srodek nadal lekko dominuje.
	weights = { [3] = 5, [4] = 7, [5] = 8, [6] = 7, [7] = 5 },
}

return LaneConfig
