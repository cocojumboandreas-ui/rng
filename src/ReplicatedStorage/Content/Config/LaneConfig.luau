--!strict
-- Content/Config/LaneConfig.luau — kolumny wejscia wrogow do rdzenia.
-- STALE przez cala gre: ZERO skalowania z numerem fali, zero rosnacego rozrzutu.
-- Srodek (4,5,6) dominuje, flanki (3,7) rzadko. Kolumny 1,2,8,9 nigdy nie sa celem.
-- Wagi = placeholder do dostrojenia (BALANCE.md), stosunek srodek:flanki ustawia Andreas.
local LaneConfig = {
	columns = { 3, 4, 5, 6, 7 },
	weights = { [3] = 1, [4] = 8, [5] = 10, [6] = 8, [7] = 1 },
}

return LaneConfig
