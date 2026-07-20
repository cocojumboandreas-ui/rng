--!strict
-- Content/Config/RevealConfig.luau — timingi teatru rewealu na kliencie wg revealTier.
-- Klient (RollRevealController) interpoluje miedzy zdefiniowanymi tierami. POST-slice VFX.
local RevealConfig = {
	tiers = {
		[1] = { buildupSec = 0.4, holdSec = 0.5, cascade = false },
		[3] = { buildupSec = 1.0, holdSec = 1.2, cascade = true },
		[5] = { buildupSec = 2.0, holdSec = 2.5, cascade = true, cinematic = true },
	},
}

return RevealConfig
