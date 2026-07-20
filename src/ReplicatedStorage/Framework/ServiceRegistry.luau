--!strict
-- Framework/ServiceRegistry.luau
-- Generyczny service-locator (wzorzec z Brainrot Fighters, bez configure()).
-- Kontrakt: register() -> initAll() -> startAll(). get() wolno dopiero w Start().
-- Framework NIE importuje z Content/. ZERO zaleznosci w dol.

export type Service = {
	Name: string?,
	Init: (() -> ())?,
	Start: (() -> ())?,
	[any]: any,
}

local ServiceRegistry = {}

local _services: { [string]: Service } = {}
local _order: { string } = {}
local _initDone = false
local _startDone = false

-- Rejestracja. Kolejnosc rejestracji = deterministyczna kolejnosc Init/Start.
function ServiceRegistry.register(name: string, service: Service): Service
	assert(type(name) == "string" and name ~= "", "service name must be a non-empty string")
	assert(_services[name] == nil, "duplicate service: " .. name)
	assert(type(service) == "table", "service '" .. name .. "' must be a table")
	_services[name] = service
	table.insert(_order, name)
	if service.Name == nil then
		service.Name = name
	end
	return service
end

-- Pobranie zarejestrowanego serwisu. Blad jesli brak. Wolac w Start(), nigdy w Init().
function ServiceRegistry.get(name: string): Service
	local s = _services[name]
	assert(s ~= nil, "service not registered: " .. tostring(name))
	return s
end

function ServiceRegistry.has(name: string): boolean
	return _services[name] ~= nil
end

-- Kolejnosc rejestracji (kopia) — do testow/diagnostyki.
function ServiceRegistry.getOrder(): { string }
	return table.clone(_order)
end

-- Init wszystkich w kolejnosci rejestracji. Init() NIE dotyka innych serwisow.
function ServiceRegistry.initAll()
	assert(not _initDone, "initAll already ran")
	_initDone = true
	for _, name in ipairs(_order) do
		local s = _services[name]
		print("[ServiceRegistry] Init " .. name)
		if type(s.Init) == "function" then
			(s.Init :: any)()
		end
	end
end

-- Start wszystkich po Init. Tu wolno ServiceRegistry.get() innych serwisow.
function ServiceRegistry.startAll()
	assert(_initDone, "startAll called before initAll")
	assert(not _startDone, "startAll already ran")
	_startDone = true
	for _, name in ipairs(_order) do
		local s = _services[name]
		print("[ServiceRegistry] Start " .. name)
		if type(s.Start) == "function" then
			(s.Start :: any)()
		end
	end
end

return ServiceRegistry
