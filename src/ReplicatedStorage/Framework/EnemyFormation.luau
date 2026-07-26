--!strict
-- Framework/EnemyFormation.luau — WSPOLNY (serwer + klient) rozstaw wrogow.
-- Wrogowie NIE ida gesiego: rozlewaja sie na 9 kolumn placu (boczny pas + glebokosc),
-- rozstaw narasta wzdluz sciezki (przy bramie gesiego -> na placu pelny wachlarz).
--
-- KLUCZOWE: pas MUSI byc IDENTYCZNY na serwerze (blokowanie/celowanie/dmg licza realna
-- pozycje) i na kliencie (render). Dlatego jest DETERMINISTYCZNY z id wroga — bez
-- dodatkowego pola w EnemySync (4B/wroga zostaje). Serwer i klient wyliczaja to samo z id.
local EnemyFormation = {}

EnemyFormation.LANE_SCALE = 0.9   -- zwezenie rozstawu bocznego (0.9 = szeroki wachlarz na cala szerokosc placu)
EnemyFormation.SPREAD_START = 0.13 -- do tego t (od bramy) ida PROSTO/gesiego (jeszcze bez rozejscia)
EnemyFormation.SPREAD_RAMP = 0.22  -- odcinek t na ktorym narasta pelny rozstaw (t: START -> START+RAMP)

local BASE_COLS = 9
local PHI = 0.6180339887498949 -- do deterministycznego "jittera" z id
local ALT = 0.7548776662466927 -- druga stala do offsetu w glab

local function frac(x: number): number
	return x - math.floor(x)
end

-- boczny offset (prostopadly do sciezki) dla wroga o danym id. Rowno pokrywa 9 kolumn placu.
function EnemyFormation.lane(id: number, isBoss: boolean?, cellSize: number?): number
	local cs = cellSize or 6
	if isBoss then
		return (frac(id * PHI) - 0.5) * 3 -- boss trzyma sie srodka
	end
	local col = (id * 4) % BASE_COLS -- 0..8 rozproszone rowno (krok 4 wzgl. 9) — wachlarz, nie sweep
	local center = (BASE_COLS - 1) / 2 -- 4
	local jitter = (frac(id * PHI) - 0.5) * cs * 0.3 -- lekki deterministyczny rozrzut (brak idealnego nakladania)
	return (col - center) * cs * EnemyFormation.LANE_SCALE + jitter
end

-- offset W GLAB (wzdluz sciezki) dla wroga o danym id — glebokosc linii, nie plasko.
function EnemyFormation.fwd(id: number, isBoss: boolean?): number
	return (frac(id * ALT) - 0.5) * (isBoss and 3 or 9)
end

-- narastanie rozstawu wzdluz sciezki t∈[0,1]: 0 przy bramie (gesiego) -> 1 na placu (pelny wachlarz).
function EnemyFormation.spreadAt(t: number): number
	return math.clamp((t - EnemyFormation.SPREAD_START) / EnemyFormation.SPREAD_RAMP, 0, 1)
end

return EnemyFormation
