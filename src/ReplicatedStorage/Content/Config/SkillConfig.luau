--!nonstrict
-- Content/Config/SkillConfig.luau — koszty/kupno drzewa umiejetnosci (dane z SkillTreeData).
-- FAZA: BEZ efektow (node bez `effect` -> StatProfile go pomija, zero zmiany Stats). Efekty dorobimy pozniej.
-- maxRank=1 -> cost = base * 1^costExp = base (koszt = wprost z crafteru). currency: coin>0 -> Coins, roll>0 -> Rolls.
-- Wezly 0/0 (informacyjne) NIE trafiaja tu -> niekupowalne (SkillService: NoSuchNode).
local Config = script.Parent
local SkillTreeData = require(Config:WaitForChild("SkillTreeData"))
local SkillCosts = require(Config:WaitForChild("SkillCosts")) -- nadpisania cen (plik dla Olo)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Enums = require(Shared:WaitForChild("Enums"))
local C = Enums.Currency

-- PREREQ pomijajacy naglowki-sekcje: wezly 0/0 (np. Player PRO Section) sa NIEKUPOWALNE, wiec nie moga byc
-- prereqiem. Dla kazdego wezla liczymy najblizszego KUPOWALNEGO przodka (idac w gore po parent), inaczej
-- galaz wiszaca pod naglowkiem (n105->n73) nigdy by sie nie odslonila ani nie dala kupic.
local parentOf, buyable = {}, {}
for _, n in ipairs(SkillTreeData) do
	parentOf[n.id] = n.parent
	local ov = SkillCosts[n.id]
	local c = (ov and ov.coin) or n.coin or 0
	local r = (ov and ov.roll) or n.roll or 0
	buyable[n.id] = (n.id ~= "root") and (c > 0 or r > 0)
end
local function buyableAncestor(id)
	local p = parentOf[id]
	while p and p ~= "root" do
		if buyable[p] then
			return p
		end
		p = parentOf[p]
	end
	return nil -- brak kupowalnego przodka -> traktuj jak dziecko roota (brak prereq)
end

local nodes = {}
for _, n in ipairs(SkillTreeData) do
	-- koszt: SkillCosts (Olo) nadpisuje SkillTreeData; brak wpisu -> domyslny z SkillTreeData. (0 jest prawidlowe.)
	local override = SkillCosts[n.id]
	local coin = (override and override.coin) or n.coin or 0
	local roll = (override and override.roll) or n.roll or 0
	if n.id ~= "root" and (coin > 0 or roll > 0) then
		nodes[n.id] = {
			label = n.label,
			currency = (coin > 0) and C.Coins or C.Rolls,
			maxRank = 1,
			base = (coin > 0) and coin or roll,
			-- kupno tylko gdy RODZIC kupiony (progresja od podstaw; blokuje kupno "?" poza kolejnoscia)
			prereqs = buyableAncestor(n.id) and { [buyableAncestor(n.id)] = 1 } or nil,
			-- BEZ `effect`: na razie zero mechaniki (StatProfile pomija). Efekty dorobimy per-wezel pozniej.
		}
	end
end

-- EFEKTY LUCK (podpiecie drzewa do szczescia). Wartosc = docelowy mnoznik "roll luck" wezla (z opisu "Nx roll luck").
-- StatProfile: skillLuckMult = 1 + Σ(V-1) po posiadanych wezlach (pojedynczy wezel = jego mnoznik; bonusy sie dodaja).
-- Placeholdery — Olo/balans dostroi. (Reszta efektow skilli = pozniejsza faza.)
local LUCK_MULT = {
	n70 = 1.5, n71 = 2, n75 = 3, -- Luck I / II / III
	n76 = 5, n79 = 7, n80 = 10, -- Strong Luck I / II / III
	n81 = 13, n82 = 18, n84 = 23, -- Mighty Luck I / II / III
	n85 = 28, n86 = 35, n87 = 44, -- Hellish Luck I / II / III
	n88 = 53, n89 = 60, n90 = 70, -- God Luck I / II / III
}
for id, v in pairs(LUCK_MULT) do
	if nodes[id] then
		nodes[id].effect = { luckMult = v }
	end
end

-- EFEKTY BOJOWE (drzewo -> plaskie Stats). StatProfile.compute sumuje effect={stat,perRank}*rank do STAT_FIELDS,
-- a CombatService.step realnie konsumuje dmgMult (dmg wiez) i fireRateMult (kadencja). Faster Shooting = delty
-- kumulatywne: I(+5) -> II(+5, razem 10) -> III(+20, razem 30). Placeholdery — Olo/balans dostroi.
local COMBAT_EFFECT = {
	n105 = { stat = "dmgMult", perRank = 0.10 }, -- Weapon Upgrade: +10% dmg jednostek
	n109 = { stat = "fireRateMult", perRank = 0.05 }, -- Faster Shooting I:  +5%
	n110 = { stat = "fireRateMult", perRank = 0.05 }, -- Faster Shooting II: +5% (skumulowane 10%)
	n111 = { stat = "fireRateMult", perRank = 0.20 }, -- Faster Shooting III:+20% (skumulowane 30%)
}
for id, eff in pairs(COMBAT_EFFECT) do
	if nodes[id] then
		nodes[id].effect = eff
	end
end
-- EFEKTY ROLL-ECONOMY (plaskie staty). Delty KUMULATYWNE wzdluz lancucha (odwzorowuja % z opisow).
--   Fast Rolls -> rollSpeed (cooldown [s], NIZEJ = szybciej; StatProfile klamruje floor 0.15).
--   Clover Chance/Frenzy/Power -> mutChance (mnoznik szansy koniczyn w ladderDepth; do +100%).
-- Placeholdery — Olo dostroi.
local MORE_EFFECT = {
	n31 = { stat = "rollSpeed", perRank = -0.15 }, n33 = { stat = "rollSpeed", perRank = -0.15 },
	n34 = { stat = "rollSpeed", perRank = -0.20 }, n35 = { stat = "rollSpeed", perRank = -0.20 },
	n36 = { stat = "rollSpeed", perRank = -0.15 }, n37 = { stat = "rollSpeed", perRank = -0.15 }, -- razem -1.0 (4.0 -> 3.0)
	n32 = { stat = "mutChance", perRank = 0.10 }, n51 = { stat = "mutChance", perRank = 0.05 },
	n52 = { stat = "mutChance", perRank = 0.05 }, n57 = { stat = "mutChance", perRank = 0.15 },
	n58 = { stat = "mutChance", perRank = 0.05 }, n59 = { stat = "mutChance", perRank = 0.10 },
	n60 = { stat = "mutChance", perRank = 0.10 }, n61 = { stat = "mutChance", perRank = 0.20 },
	n62 = { stat = "mutChance", perRank = 0.20 },
}
for id, eff in pairs(MORE_EFFECT) do
	if nodes[id] then
		nodes[id].effect = eff
	end
end
-- x16/x32/x64 Clover (n53/n63/n64) = SUFIT drabiny koniczyn (MutationConfig.tierUnlock) — gating w RollService.
-- Explosive Ammo (n78/n95-98), Military Convoy (n106), Nuke (n107), Air Raid (n108): efekty BEHAWIORALNE
-- (nie plaskie staty) — CombatService/WaveService/RollService.

return {
	costExp = 1.0, -- maxRank=1, wiec cost = base (koszt wprost z projektu)
	nodes = nodes,
}
