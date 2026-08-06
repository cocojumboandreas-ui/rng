--!nonstrict
-- StarterPlayerScripts/Controllers/PerfSettings.luau  (KLIENT — modul stanu)
-- Klient-side przelaczniki wydajnosci (panel Settings). Kontrolery czytaja PerfSettings.get(key)
-- i pomijaja drogie rzeczy gdy wylaczone. Czysto wizualne — serwer i logika bez zmian.
-- Domyslnie WSZYSTKO wlaczone (obecne zachowanie); gracz wylacza co go muli.
local PerfSettings = {}

-- key -> bool (true = efekt WIDOCZNY/wlaczony)
local _state = {
	soldierAnim = true, -- animacja konczyn/kol wrogow (marsz, wirniki)
	attackAnim = true, -- FX strzalow WROGÓW z INNYCH plotow (twoj plot zawsze widoczny)
	showOthers = true, -- renderuj wrogow z cudzych plotow (false = tylko twoj plot)
	damageCounter = true, -- paski/liczby HP nad wrogami i jednostkami
	coinAnim = true, -- animacje/FX zdobytych monet
}

local _listeners = {} -- { fn(key, value), ... }

function PerfSettings.get(key: string): boolean
	return _state[key] ~= false
end

function PerfSettings.set(key: string, value: boolean)
	value = value and true or false
	if _state[key] == value then return end
	_state[key] = value
	for _, fn in ipairs(_listeners) do
		pcall(fn, key, value)
	end
end

function PerfSettings.toggle(key: string): boolean
	PerfSettings.set(key, not PerfSettings.get(key))
	return PerfSettings.get(key)
end

-- rejestruj callback na kazda zmiane (do live-odswiezania UI/renderu)
function PerfSettings.onChanged(fn)
	table.insert(_listeners, fn)
end

-- ── WARSTWA AUTO (PerfGovernor) ───────────────────────────────────────────────
-- Osobna od recznych przelacznikow: panel ⚙ pokazuje/steruje TYLKO recznymi (get/set/toggle),
-- governor obniza jakosc przez _auto + _budgets. Efektywny stan efektu = eff(key) = reczny AND auto.
-- Kontrolery kosztownych efektow czytaja eff() zamiast get(); budzety FX czytaja budget(name).
local _auto = {} -- key -> false gdy governor wylaczyl; brak wpisu/true = auto pozwala
local _budgets = {} -- name -> mnoznik 0..1 (skala liczby czastek/FX); brak = 1
local _tier = 1 -- 1=Ultra .. 5=Potato (info/debug)

function PerfSettings.eff(key: string): boolean
	return PerfSettings.get(key) and _auto[key] ~= false
end

function PerfSettings.budget(name: string, default: number?): number
	local v = _budgets[name]
	if v == nil then return default or 1 end
	return v
end

function PerfSettings.tier(): number
	return _tier
end

-- wolane TYLKO przez PerfGovernor przy zmianie tieru (atomowa podmiana calej warstwy auto)
function PerfSettings.applyTier(tier: number, auto: { [string]: boolean }, budgets: { [string]: number })
	_tier = tier
	_auto = auto or {}
	_budgets = budgets or {}
	for _, fn in ipairs(_listeners) do
		pcall(fn, "__tier", tier)
	end
end

return PerfSettings
