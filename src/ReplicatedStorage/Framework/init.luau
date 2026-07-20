--!strict
-- Framework: minimalny ServiceRegistry (Init -> Start).
-- STUB szkieletu. Logika dojdzie z architektura.

export type Service = {
	Name: string?,
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
	[any]: any,
}

local Framework = {}
Framework.__index = Framework

local _services: { [string]: Service } = {}
local _order: { string } = {}
local _started = false

-- Zarejestruj serwis pod nazwa. Zwraca ten sam obiekt (do lancuchowania).
function Framework.register(name: string, service: Service): Service
	assert(not _services[name], "Service juz zarejestrowany: " .. name)
	_services[name] = service
	table.insert(_order, name)
	return service
end

-- Pobierz zarejestrowany serwis.
function Framework.get(name: string): Service
	local s = _services[name]
	assert(s, "Brak serwisu: " .. name)
	return s
end

-- Wywolaj Init() na wszystkich w kolejnosci rejestracji, potem Start().
function Framework.start(): ()
	assert(not _started, "Framework juz wystartowal")
	_started = true
	for _, name in ipairs(_order) do
		local s = _services[name]
		if s.Init then s:Init() end
	end
	for _, name in ipairs(_order) do
		local s = _services[name]
		if s.Start then s:Start() end
	end
end

return Framework
