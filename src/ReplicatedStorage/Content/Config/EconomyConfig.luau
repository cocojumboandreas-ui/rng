--!strict
-- Content/Config/EconomyConfig.luau — monety, offline, nagrody.
local EconomyConfig = {
	offline = { capHours = 10, ratePerHourFromStats = true, rollsPerHour = 20 }, -- coins=Stats.offlineRate; rolki=rollsPerHour (placeholder, Olo tuninguje)
	killReward = 2, -- monety za zabicie wroga (baza; x Stats.coinMult)
}

return EconomyConfig
