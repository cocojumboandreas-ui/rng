--!nonstrict
-- WR_P0FixTest  (TYMCZASOWY — bramka fixow P0; USUŃ po zielonej weryfikacji)
-- Asercje dla 4 fixow korektnosci z docs/PERF_AUDIT.md, wzorzec jak reszta harnessow:
-- serwerowy skrypt uruchamiany w playtescie, uzywa hookow _ForTest, drukuje PASS/FAIL + podsumowanie.
--   FIX 1: klamra MAX_STEPS_PER_FRAME na akumulatorze (anty-spirala smierci)
--   FIX 2: chunkowanie EnemySync (limit ~900B UnreliableRemoteEvent)
--   FIX 4a: WaveService._runGen zerowany przy wyjsciu gracza
--   FIX 4b: CombatService._unitHpSend czyszczony w ClearPlot
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local reg = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("ServiceRegistry"))

local passed, failed = 0, 0
local function check(name, cond, extra)
	if cond then
		passed += 1
		print(("  [PASS] %s"):format(name))
	else
		failed += 1
		warn(("  [FAIL] %s%s"):format(name, extra and ("  -> " .. tostring(extra)) or ""))
	end
end

task.spawn(function()
	local Combat = reg.get("CombatService")
	local Wave = reg.get("WaveService")
	print("=== WR_P0FixTest ===")

	-- ── FIX 1: klamra akumulatora ─────────────────────────────────────────────
	do
		local c = Combat._GetSyncConstsForTest()
		Combat._ResetAccForTest()
		-- 500 ms przy dtStep=100ms => 5 zaleglych krokow, klamra do MAX_STEPS_PER_FRAME (3)
		local steps1 = Combat._AdvanceAccumulatorForTest(0.5)
		local acc1 = Combat._GetAccForTest()
		local steps2 = Combat._AdvanceAccumulatorForTest(0.5)
		local acc2 = Combat._GetAccForTest()
		check("FIX1 liczba krokow == MAX_STEPS_PER_FRAME", steps1 == c.maxSteps, ("steps=%d max=%d"):format(steps1, c.maxSteps))
		check("FIX1 dlug PORZUCONY (acc < dtStep)", acc1 < c.dtStep, ("acc=%.4f dt=%.4f"):format(acc1, c.dtStep))
		check("FIX1 akumulator NIE rosnie miedzy wywolaniami", acc2 <= acc1 + 1e-6 and steps2 == steps1, ("acc1=%.4f acc2=%.4f s2=%d"):format(acc1, acc2, steps2))
	end

	-- ── FIX 2: chunkowanie EnemySync ─────────────────────────────────────────
	do
		local c = Combat._GetSyncConstsForTest()
		local N = 500
		local enemies, pathById = {}, {}
		for i = 1, N do
			local pt = i / (N + 1) -- rosnaco: wyzszy i => wyzszy pathT (blizej rdzenia)
			enemies[i] = { id = i, pathT = pt, hp = 100, maxHp = 100 }
			pathById[i] = pt
		end
		local chunks, total, sent = Combat._BuildSyncChunksForTest(enemies)
		local expectChunks = math.ceil(N / c.perPacket)
		check("FIX2 total == N", total == N, ("total=%d"):format(total))
		check("FIX2 sent == N (ponizej capu)", sent == N, ("sent=%d"):format(sent))
		check("FIX2 liczba chunkow == ceil(N/perPacket)", #chunks == expectChunks, ("#chunks=%d exp=%d"):format(#chunks, expectChunks))

		-- round-trip: rozpakuj kazdy chunk NIEZALEZNIE
		local seenIds, sumRecords = {}, 0
		local minPathPrevChunk = math.huge -- min pathT poprzedniego chunku (chunk 0 = najblizsi rdzenia)
		local allUnder900, headerOk, monotonic = true, true, true
		for ci = 1, #chunks do
			local buf = chunks[ci]
			local len = buffer.len(buf)
			if len > 900 then allUnder900 = false end
			local hdrIdx = buffer.readu8(buf, 0)
			local hdrCnt = buffer.readu8(buf, 1)
			if hdrIdx ~= (ci - 1) or hdrCnt ~= expectChunks then headerOk = false end
			local n = (len - 2) // 4
			sumRecords += n
			local maxPathThis, minPathThis = -math.huge, math.huge
			for r = 0, n - 1 do
				local off = 2 + r * 4
				local id = buffer.readu16(buf, off)
				local pt = buffer.readu8(buf, off + 2) / 255
				seenIds[id] = true
				local orig = pathById[id]
				if orig then
					if orig > maxPathThis then maxPathThis = orig end
					if orig < minPathThis then minPathThis = orig end
				end
			end
			-- chunk ci musi miec wrogow DALEJ od rdzenia niz chunk ci-1 => maxPathThis <= minPathPrevChunk
			if ci > 1 and maxPathThis > minPathPrevChunk + 1e-9 then monotonic = false end
			minPathPrevChunk = minPathThis
		end
		local uniqueCount = 0
		for _ in pairs(seenIds) do uniqueCount += 1 end
		check("FIX2 kazdy chunk <= 900B", allUnder900)
		check("FIX2 naglowek [chunkIdx,chunkCount] poprawny", headerOk)
		check("FIX2 suma rekordow w chunkach == N", sumRecords == N and uniqueCount == N, ("sum=%d uniq=%d"):format(sumRecords, uniqueCount))
		check("FIX2 chunk 0 = wrogowie najblizsi rdzenia (pathT malejaco)", monotonic)

		-- hard cap: znacznie wiecej niz perPacket*maxChunks => sent uciete, chunkow == maxChunks
		local BIG = c.perPacket * c.maxChunks + 250
		local big = {}
		for i = 1, BIG do big[i] = { id = i, pathT = i / (BIG + 1), hp = 1, maxHp = 1 } end
		local bchunks, btotal, bsent = Combat._BuildSyncChunksForTest(big)
		check("FIX2 hard-cap: sent == perPacket*maxChunks", bsent == c.perPacket * c.maxChunks, ("sent=%d"):format(bsent))
		check("FIX2 hard-cap: #chunks == maxChunks", #bchunks == c.maxChunks, ("#=%d"):format(#bchunks))
		check("FIX2 hard-cap: total nadal liczy wszystkich", btotal == BIG, ("total=%d"):format(btotal))
	end

	-- ── FIX 4a: WaveService._runGen zerowany przy wyjsciu ────────────────────
	do
		local fakePlayer = { __t = "p4a" }
		Wave._SeedRunGenForTest(fakePlayer, 7)
		check("FIX4a seed widoczny", Wave._GetRunGenForTest(fakePlayer) == 7)
		Wave._CleanupPlayerForTest(fakePlayer)
		check("FIX4a _runGen == nil po cleanup", Wave._GetRunGenForTest(fakePlayer) == nil)
	end

	-- ── FIX 4b: CombatService._unitHpSend czyszczony w ClearPlot ──────────────
	do
		local fakePlayer = { __t = "p4b" }
		local pid = "unit_p4b_1"
		Combat._SeedUnitHpForTest(fakePlayer, pid, 42)
		local send = Combat._GetUnitHpSendForTest()
		local uhp = Combat._GetUnitHpForTest(fakePlayer)
		check("FIX4b seed: _unitHp + _unitHpSend obecne", uhp and uhp[pid] == 42 and send[pid] ~= nil)
		Combat.ClearPlot(fakePlayer)
		local send2 = Combat._GetUnitHpSendForTest()
		check("FIX4b _unitHp[player] == nil po ClearPlot", Combat._GetUnitHpForTest(fakePlayer) == nil)
		check("FIX4b _unitHpSend[pid] == nil po ClearPlot", send2[pid] == nil)
	end

	print(("=== WYNIK: %d PASS / %d FAIL ==="):format(passed, failed))
	if failed == 0 then
		print(">>> WSZYSTKIE ZIELONE <<<")
	else
		warn((">>> %d TEST(OW) CZERWONYCH <<<"):format(failed))
	end
end)
