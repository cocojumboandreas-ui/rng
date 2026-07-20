--!strict
-- Content/Config/EconomyConfig.luau — monety, offline, nagrody.
local EconomyConfig = {
	offline = { capHours = 10, ratePerHourFromStats = true }, -- rate = Stats.offlineRate (offline earn POST-BRAMKA)
	killReward = 2, -- monety za zabicie wroga (baza; x Stats.coinMult)
}

return EconomyConfig
