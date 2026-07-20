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

-- Srodek footprintu w swiecie (bez orientacji — BuildService doklada faceDirection).
function GridMath.cellToWorld(gridOrigin: CFrame, cellSize: number, cellX: number, cellZ: number, fp: { w: number, d: number }): CFrame
	local cx = (cellX - 0.5 + (fp.w - 1) * 0.5) * cellSize
	local cz = (cellZ - 0.5 + (fp.d - 1) * 0.5) * cellSize
	return CFrame.new(gridOrigin.Position + Vector3.new(cx, 0, cz))
end

return GridMath
