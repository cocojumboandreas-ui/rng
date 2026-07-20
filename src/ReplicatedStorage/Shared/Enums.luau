--!strict
-- Shared/Enums.luau — stale enumy (string-backed). Wspoldzielone server+client.
local Enums = {}

Enums.RunPhase = {
	Building = "Building",
	WaveActive = "WaveActive",
	Summary = "Summary",
}

Enums.WaveEndReason = {
	Cleared = "Cleared", -- kills == pool
	CoreDestroyed = "CoreDestroyed", -- koniec runu
}

Enums.Currency = {
	Coins = "Coins",
	Rolls = "Rolls", -- spendableRolls (NIGDY lifetimeRolls)
}

Enums.UnitKind = {
	Weapon = "Weapon", -- jednostka bojowa (ma combat)
	Block = "Block", -- sciana/przeszkoda (ma hp, brak combat)
}

table.freeze(Enums.RunPhase)
table.freeze(Enums.WaveEndReason)
table.freeze(Enums.Currency)
table.freeze(Enums.UnitKind)
table.freeze(Enums)

return Enums
