--!strict
-- Content/Config/EconomyConfig.luau — monety, offline, nagrody.
local EconomyConfig = {
	-- OFFLINE: monety = Stats.offlineRate/h; rolki offline = rollsPerHour spinow/h (REALNIE rolowane w jednostki,
	-- nie waluta). dropsShown = ile kart w panelu (top najrzadsze). maxRollsSim = sufit petli symulacji (perf).
	-- doubleProductId = DevProduct 49R na CLAIM X2 (2x); 0 = placeholder -> przycisk X2 ukryty do wpisania ID.
	offline = { capHours = 10, ratePerHourFromStats = true, rollsPerHour = 20, dropsShown = 5, maxRollsSim = 4000, doubleProductId = 0 },
	killReward = 2, -- monety za zabicie wroga (baza; x Stats.coinMult)
}

return EconomyConfig
