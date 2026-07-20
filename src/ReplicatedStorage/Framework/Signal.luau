--!nonstrict
-- Framework/Signal.luau — lekki sygnal (event) server-side.
-- Komunikacja "w gore zaleznosci": np. CombatService emituje EnemyDied, WaveService subskrybuje.
-- Handlery odpalane natychmiast, kazdy w osobnym watku (task.spawn) — blad lub yield jednego
-- handlera nie psuje emitera ani pozostalych handlerow.

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

-- Zwraca connection z :Disconnect() i polem .Connected.
function Signal:Connect(fn)
	assert(type(fn) == "function", "Signal:Connect expects a function")
	local handlers = self._handlers
	table.insert(handlers, fn)

	local connection = { Connected = true }
	function connection:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		local idx = table.find(handlers, fn)
		if idx then
			table.remove(handlers, idx)
		end
	end
	return connection
end

function Signal:Fire(...)
	-- kopia listy: handler moze rozlaczyc siebie/innych w trakcie Fire
	local snapshot = table.clone(self._handlers)
	for _, fn in ipairs(snapshot) do
		task.spawn(fn, ...)
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
