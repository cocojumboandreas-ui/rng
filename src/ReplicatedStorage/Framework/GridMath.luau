--!strict
-- Framework/GridMath.luau — czysta matematyka siatki (ZERO importow z Content).
-- Konwencja (spojna z PlotService): gridOrigin = rog min (granica komorki 1,1),
-- osie width=+X, depth=+Z. Srodek komorki 1-indeks (x,z) =
--   gridOrigin.Position + (cellSize*(x-0.5), 0, cellSize*(z-0.5)).
local GridMath = {}

-- Klucz kratki do slownika occupancy.
function GridMath.key(x: number, z: number): string
	return x .. ":" .. z
end

-- Lista kratek zajmowanych przez footprint {w,d} zakotwiczony w (cellX,cellZ).
function GridMath.footprintCells(cellX: number, cellZ: number, fp: { w: number, d: number })
	local cells = {}
	for dx = 0, fp.w - 1 do
		for dz = 0, fp.d - 1 do
			cells[#cells + 1] = { x = cellX + dx, z = cellZ + dz }
		end
	end
	return cells
end

-- Pozycja na polilinii (tablica Vector3) dla t∈[0,1], rowno po segmentach.
-- Uzywane przez klienta (EnemyRenderController) do interpolacji pozycji wroga z pathT.
-- Serwerowy CombatService ma rownowazna logike inline (na CFrame'ach pathNodes).
function GridMath.polylinePos(nodes: { Vector3 }, t: number): Vector3
	local n = #nodes
	if n == 0 then
		return Vector3.zero
	end
	if n == 1 then
		return nodes[1]
	end
	local tt = math.clamp(t, 0, 1)
	local scaled = tt * (n - 1)
	local i = math.floor(scaled) + 1
	if i >= n then
		return nodes[n]
	end
	local frac = scaled - (i - 1)
	return nodes[i]:Lerp(nodes[i + 1], frac)
end

-- Srodek footprintu w swiecie (bez orientacji — BuildService doklada faceDirection).
function GridMath.cellToWorld(gridOrigin: CFrame, cellSize: number, cellX: number, cellZ: number, fp: { w: number, d: number }): CFrame
	local cx = (cellX - 0.5 + (fp.w - 1) * 0.5) * cellSize
	local cz = (cellZ - 0.5 + (fp.d - 1) * 0.5) * cellSize
	return CFrame.new(gridOrigin.Position + Vector3.new(cx, 0, cz))
end

return GridMath
