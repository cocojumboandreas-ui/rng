--!nocheck
-- job StudioBridge: validate_modules (POLOWA 1 — strona Studio)
-- ------------------------------------------------------------------------------------
-- Skanuje ModuleScript-y w 7 wezlach mapowanych w default.project.json:
--   RS.Framework, RS.Content, RS.Shared, SSS.Services, SSS.init,
--   StarterPlayerScripts.Controllers, StarterPlayerScripts.init
-- (SSS.Server/vendor NIE jest skanowany — poza lista wezlow). init.server/init.client
-- to Script/LocalScript, nie ModuleScript, wiec naturalnie wypadaja ze skanu.
--
-- Dla kazdego modulu zwraca wiersz:
--   { path, className, lineCount, sourceLen, sha256, tailOk, tailLast }
-- Wyjscie: JSON (jedna tablica wierszy), nic wiecej. NIE require'uje modulow
-- (statyczna analiza zrodla — zero ryzyka odpalenia kodu / brudzenia placu).
--
-- NORMALIZACJA (MUSI byc identyczna z POLOWA 2 / validate_modules.py, inaczej hash sie rozjedzie):
--   1. CRLF i CR -> LF
--   2. usun BOM U+FEFF z poczatku (UTF-8: bajty EF BB BF), jesli jest
--   3. usun trailing whitespace [ \t] z KAZDEJ linii
--   4. usun puste linie z samego konca, dopisz dokladnie jedno \n
-- sha256 liczony na tak znormalizowanym zrodle (bajty UTF-8). sourceLen = dlugosc w BAJTACH
-- znormalizowanego zrodla (Python liczy len(...encode('utf-8')) — zgodnie).

local HttpService = game:GetService("HttpService")

-- ── SHA-256 (czysty Luau, bit32) ───────────────────────────────────────────────
local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local band, bor, bxor, bnot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot
local rshift, lshift = bit32.rshift, bit32.lshift
local function rrot(x, n) return bor(rshift(x, n), lshift(x, 32 - n)) end
local MASK = 0xffffffff

local function beword(w)
	return string.char(band(rshift(w, 24), 0xff), band(rshift(w, 16), 0xff), band(rshift(w, 8), 0xff), band(w, 0xff))
end

local function sha256(msg)
	local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
	local bitlen = #msg * 8
	msg = msg .. "\128"
	while (#msg % 64) ~= 56 do msg = msg .. "\0" end
	local hi = math.floor(bitlen / 4294967296)
	local lo = bitlen % 4294967296
	msg = msg .. beword(hi) .. beword(lo)

	for i = 1, #msg, 64 do
		local w = {}
		for j = 0, 15 do
			local a, b, c, d = string.byte(msg, i + j * 4, i + j * 4 + 3)
			w[j] = bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d)
		end
		for j = 16, 63 do
			local s0 = bxor(rrot(w[j - 15], 7), rrot(w[j - 15], 18), rshift(w[j - 15], 3))
			local s1 = bxor(rrot(w[j - 2], 17), rrot(w[j - 2], 19), rshift(w[j - 2], 10))
			w[j] = band(w[j - 16] + s0 + w[j - 7] + s1, MASK)
		end
		local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
		for j = 0, 63 do
			local S1 = bxor(rrot(e, 6), rrot(e, 11), rrot(e, 25))
			local ch = bxor(band(e, f), band(bnot(e), g))
			local t1 = band(h + S1 + ch + K[j + 1] + w[j], MASK)
			local S0 = bxor(rrot(a, 2), rrot(a, 13), rrot(a, 22))
			local maj = bxor(band(a, b), band(a, c), band(b, c))
			local t2 = band(S0 + maj, MASK)
			h = g; g = f; f = e; e = band(d + t1, MASK); d = c; c = b; b = a; a = band(t1 + t2, MASK)
		end
		H[1] = band(H[1] + a, MASK); H[2] = band(H[2] + b, MASK); H[3] = band(H[3] + c, MASK); H[4] = band(H[4] + d, MASK)
		H[5] = band(H[5] + e, MASK); H[6] = band(H[6] + f, MASK); H[7] = band(H[7] + g, MASK); H[8] = band(H[8] + h, MASK)
	end

	local out = {}
	for i = 1, 8 do out[i] = string.format("%08x", H[i]) end
	return table.concat(out)
end

-- ── normalizacja + split ────────────────────────────────────────────────────────
local function splitLines(s)
	local t, start = {}, 1
	while true do
		local nl = string.find(s, "\n", start, true)
		if not nl then t[#t + 1] = string.sub(s, start); break end
		t[#t + 1] = string.sub(s, start, nl - 1)
		start = nl + 1
	end
	return t
end

local function normalize(s)
	s = (string.gsub(s, "\r\n", "\n"))
	s = (string.gsub(s, "\r", "\n"))
	if string.sub(s, 1, 3) == "\239\187\191" then s = string.sub(s, 4) end -- BOM UTF-8
	local lines = splitLines(s)
	for i = 1, #lines do lines[i] = (string.gsub(lines[i], "[ \t]+$", "")) end
	while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
	return table.concat(lines, "\n") .. "\n"
end

-- ── skaner ogona (od konca, linia po linii; pomija puste / komentarze --  / bloki --[[ ]] / --[=[ ]=]) ──
-- Zwraca tailOk (ostatnia znaczaca instrukcja to `return <cokolwiek>`) + tailLast (ta linia).
local function blockCloseLevel(line) -- linia konczy sie ]] lub ]=..=] i NIE zawiera pasujacego otwarcia?
	local close = string.match(line, "%](=*)%]%s*$")
	if not close then return nil end
	local lvl = #close
	if string.find(line, "%-%-%[" .. string.rep("=", lvl) .. "%[", 1) then return nil end -- otwarcie w tej samej linii -> nie wielolinijkowy
	return lvl
end

local function stripTrailingComment(line)
	local p = string.find(line, "%-%-", 1) -- pierwsze `--` (pragmatyka: ogon modulu nie ma `--` w stringu)
	if p then return string.sub(line, 1, p - 1) end
	return line
end

local function tailAnalysis(lines)
	local i = #lines
	local awaitOpen = nil -- gdy != nil: skanujemy w gore szukajac otwarcia bloku danego poziomu
	while i >= 1 do
		local line = (string.gsub(lines[i], "^%s+", ""))
		line = (string.gsub(line, "%s+$", ""))
		if awaitOpen ~= nil then
			if string.find(line, "%-%-%[" .. string.rep("=", awaitOpen) .. "%[", 1) then awaitOpen = nil end
			i = i - 1
		elseif line == "" then
			i = i - 1
		else
			local code = (string.gsub(stripTrailingComment(line), "%s+$", ""))
			if code == "" then
				-- cala linia to komentarz; jesli to zamkniecie bloku wielolinijkowego -> szukaj otwarcia w gore
				local lvl = blockCloseLevel(line)
				if lvl ~= nil then awaitOpen = lvl end
				i = i - 1
			else
				local isReturn = false
				local rest = string.match(code, "^return(.*)$")
				if rest ~= nil then
					local nxt = string.sub(rest, 1, 1)
					if rest == "" or not string.match(nxt, "[%w_]") then isReturn = true end
				end
				return isReturn, lines[i]
			end
		end
	end
	return false, ""
end

-- ── skan wezlow ──────────────────────────────────────────────────────────────────
-- 7 wezlow z default.project.json (Studio-path -> GetService + sciezka dzieci).
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SPS = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")

local scanRoots = {}
local function addRoot(inst)
	if inst then scanRoots[#scanRoots + 1] = inst end
end
addRoot(RS:FindFirstChild("Framework"))
addRoot(RS:FindFirstChild("Content"))
addRoot(RS:FindFirstChild("Shared"))
addRoot(SSS:FindFirstChild("Services"))
addRoot(SSS:FindFirstChild("init"))
addRoot(SPS:FindFirstChild("Controllers"))
addRoot(SPS:FindFirstChild("init"))

local rows = {}
local seen = {}
for _, root in ipairs(scanRoots) do
	-- root moze byc sam ModuleScript (folderyzacja init.luau) albo kontener z dziecmi
	local candidates = {}
	if root:IsA("ModuleScript") then candidates[#candidates + 1] = root end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ModuleScript") then candidates[#candidates + 1] = d end
	end
	for _, m in ipairs(candidates) do
		if not seen[m] then
			seen[m] = true
			local norm = normalize(m.Source)
			local lines = splitLines(norm)
			-- lines konczy sie pustym elementem (norm konczy sie \n); lineCount = liczba realnych linii
			local lineCount = #lines - 1
			local tailOk, tailLast = tailAnalysis(lines)
			rows[#rows + 1] = {
				path = m:GetFullName(),
				className = m.ClassName,
				lineCount = lineCount,
				sourceLen = #norm,
				sha256 = sha256(norm),
				tailOk = tailOk,
				tailLast = tailLast,
			}
		end
	end
end

return HttpService:JSONEncode(rows)
