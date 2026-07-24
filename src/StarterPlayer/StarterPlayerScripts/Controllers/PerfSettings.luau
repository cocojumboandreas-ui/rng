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

return PerfSettings
