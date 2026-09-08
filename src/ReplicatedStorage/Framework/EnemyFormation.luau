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
EnemyFormation.SPREAD_START = 0.16 -- do tego t ida WASKO przez brame (nie przenikaja przez wieze/ploty przy wejsciu); potem sie rozlewaja
EnemyFormation.SPREAD_RAMP = 0.10  -- pelny rozstaw juz po ~10% sciezki OD progu -> tuz ZA brama szybko sie rozsypuja na boki
EnemyFormation.CONVERGE_START = 0.90 -- od tego t wrogowie ZWEZAJA sie z powrotem do SRODKA (0.90 = trzymaja sloty dluzej, zbiegaja dopiero tuz przy rdzeniu -> mniej zbijania przy bloku)

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

EnemyFormation.COL_JITTER = 1.05 -- boczny rozrzut w OBREBIE kolumny (× cellSize): ~1.0 = wypelnia szerokosc kolumny -> ciagly losowy rozrzut miedzy slotami (nie 5 dyskretnych linii)

-- offset W GLAB (wzdluz sciezki) dla wroga o danym id — glebokosc linii, nie plasko.
function EnemyFormation.fwd(id: number, isBoss: boolean?): number
	return (frac(id * ALT) - 0.5) * (isBoss and 4 or 14) -- ±7 (bylo ±4.5): wieksze przetasowanie front-tyl -> luzniej
end

-- BOCZNY offset dla KONKRETNEJ KOLUMNY CELU (1..width) — DOKLADNE wyrownanie do kolumny siatki bazy,
-- zeby wrog stanal dokladnie nad kolumna, w ktorej gracz stawia bloki. BEZ LANE_SCALE (to nie kosmetyczny
-- wachlarz, tylko realny cel). center = srodkowa kolumna (width nieparzysty -> jedna, np. 9 -> 5).
-- Znak (ktora strona) obsluguje perp renderu/serwera — serwer i klient uzywaja tej samej konwencji.
function EnemyFormation.laneForColumn(col: number, width: number?, cellSize: number?, id: number?): number
	local w = width or 9
	local cs = cellSize or 6
	local center = (w + 1) / 2 -- 9 -> 5.0
	local base = (col - center) * cs
	-- deterministyczny jitter boczny z id: wrogowie w tej samej kolumnie NIE stoja w idealnej linii,
	-- tylko rozlewaja sie luzno w obrebie kolumny. Wspolny serwer+klient (to samo id) -> render == realna
	-- pozycja (blokowanie/celowanie zgodne). Skalowany spreadAt() w renderze -> przy rdzeniu i tak zbiega do srodka.
	local jitter = id and (frac(id * PHI) - 0.5) * cs * EnemyFormation.COL_JITTER or 0
	return base + jitter
end

-- narastanie rozstawu wzdluz sciezki t∈[0,1]: 0 przy bramie (gesiego) -> 1 na placu (pelny wachlarz).
function EnemyFormation.spreadAt(t: number): number
	local ramp = math.clamp((t - EnemyFormation.SPREAD_START) / EnemyFormation.SPREAD_RAMP, 0, 1) -- brama (0) -> plac (pelny wachlarz, 1)
	local cs = EnemyFormation.CONVERGE_START
	if cs and cs < 1 and t > cs then
		-- PRZED RDZENIEM: rozstaw wraca do 0 -> boczni schodza do srodka, wszyscy zbijaja sie przed rdzeniem
		return ramp * math.clamp((1 - t) / (1 - cs), 0, 1)
	end
	return ramp
end

return EnemyFormation
