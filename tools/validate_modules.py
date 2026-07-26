#!/usr/bin/env python3
# validate_modules.py  —  POLOWA 2 (host) walidatora modulow StudioBridge.
# ------------------------------------------------------------------------------------
# Bramka po pushu: wykrywa rozjechanie Studio vs dysk w pipelinie MCP/StudioBridge
# (rojo build waliduje TYLKO dysk, wiec uciety push jest tam niewidoczny).
#
# Czyta default.project.json, mapuje 7 wezlow Studio -> katalogi na dysku, normalizuje
# pliki dysku TA SAMA funkcja co job Luau (validate_modules.luau), i porownuje z wynikiem
# ze Studio (JSON z joba). Raportuje TYLKO bledy w trzech kategoriach:
#   BRAK RETURNU  — tailOk == false (modul nie konczy sie `return`)
#   ROZJECHANIE   — sha256 Studio != sha256 dysku (lapie uciety/zmieniony push gdziekolwiek)
#   BRAK PLIKU    — modul jest po jednej stronie, brak po drugiej
# Zero bledow -> "OK: N modulow zgodnych" + exit 0. Cokolwiek -> exit != 0 (bramkowalne).
#
# Zrodlo Studio (dwa tryby):
#   --studio-json PATH|-   : czyta wynik joba z pliku / stdin (offline; tez gdy hub :9977 down)
#   (domyslnie)            : POST kodu joba do huba StudioBridge :9977, parsuje {ok, result}
#
# NORMALIZACJA (MUSI byc identyczna z validate_modules.luau):
#   1. CRLF i CR -> LF
#   2. usun BOM U+FEFF z poczatku, jesli jest
#   3. usun trailing whitespace [ \t] z KAZDEJ linii
#   4. usun puste linie z samego konca, dopisz dokladnie jedno \n
# sha256 = hash znormalizowanego zrodla (bajty UTF-8). sourceLen = dlugosc w BAJTACH UTF-8.
#
# UWAGA (zapis tego pliku): .py/.ps1 zapisuj przez [System.IO.File]::WriteAllText z
# UTF8Encoding($false) — Set-Content -Encoding UTF8 w PS5 dopisuje BOM i Python wywala
# SyntaxError. Pliki z dysku czytamy z encoding="utf-8-sig" (tolerancja BOM).

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.request

# 7 wezlow Studio skanowanych przez job (SSS.Server/vendor CELOWO poza lista).
ALLOWED_NODES = {
    "ReplicatedStorage.Framework",
    "ReplicatedStorage.Content",
    "ReplicatedStorage.Shared",
    "ServerScriptService.Services",
    "ServerScriptService.init",
    "StarterPlayer.StarterPlayerScripts.Controllers",
    "StarterPlayer.StarterPlayerScripts.init",
}

_TRAIL_WS = re.compile(r"[ \t]+$")


def normalize(s: str) -> str:
    """Identyczna z validate_modules.luau: patrz naglowek pliku."""
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    if s.startswith("\ufeff"):
        s = s[1:]
    lines = [_TRAIL_WS.sub("", ln) for ln in s.split("\n")]
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines) + "\n"


def _block_close_level(line):
    m = re.search(r"\](=*)\]\s*$", line)
    if not m:
        return None
    lvl = len(m.group(1))
    if re.search(r"--\[" + "=" * lvl + r"\[", line):  # otwarcie w tej samej linii
        return None
    return lvl


def _strip_trailing_comment(line):
    p = line.find("--")
    return line[:p] if p != -1 else line


def tail_analysis(lines):
    """Od konca, linia po linii; pomija puste / komentarze -- i bloki --[[ ]] / --[=[ ]=].
    Zwraca (tailOk, tailLast). Mirror funkcji Luau."""
    i = len(lines) - 1
    await_open = None
    while i >= 0:
        line = lines[i].strip()
        if await_open is not None:
            if re.search(r"--\[" + "=" * await_open + r"\[", line):
                await_open = None
            i -= 1
        elif line == "":
            i -= 1
        else:
            code = _strip_trailing_comment(line).rstrip()
            if code == "":
                lvl = _block_close_level(line)
                if lvl is not None:
                    await_open = lvl
                i -= 1
            else:
                m = re.match(r"^return(.*)$", code)
                is_return = False
                if m is not None:
                    rest = m.group(1)
                    nxt = rest[:1]
                    if rest == "" or not re.match(r"[A-Za-z0-9_]", nxt):
                        is_return = True
                return is_return, lines[i]
    return False, ""


def analyze_source(raw: str) -> dict:
    norm = normalize(raw)
    b = norm.encode("utf-8")
    lines = norm.split("\n")  # konczy sie "" (norm konczy sie \n) — jak splitLines w Luau
    line_count = norm.count("\n")
    tail_ok, tail_last = tail_analysis(lines)
    return {
        "lineCount": line_count,
        "sourceLen": len(b),
        "sha256": hashlib.sha256(b).hexdigest(),
        "tailOk": tail_ok,
        "tailLast": tail_last,
    }


# ── mapowanie default.project.json -> (studioPath, diskDir) dla 7 wezlow ──────────
def collect_mapped_nodes(project: dict):
    tree = project.get("tree", {})
    out = {}  # studioPath -> diskRelPath

    def walk(node, path_parts):
        if not isinstance(node, dict):
            return
        if "$path" in node:
            studio = ".".join(path_parts)
            out[studio] = node["$path"]
            return
        for k, v in node.items():
            if k.startswith("$"):
                continue
            walk(v, path_parts + [k])

    walk(tree, [])
    # tylko 7 dozwolonych (odetnij SSS.Server itd.)
    return {k: v for k, v in out.items() if k in ALLOWED_NODES}


def disk_modules(repo_root: str, nodes: dict):
    """Zwraca {studioDottedPath: absFilePath} dla ModuleScript-ow na dysku pod 7 wezlami.
    ModuleScript = *.luau ktore NIE jest *.server.luau / *.client.luau; init.luau folderyzuje
    folder w ModuleScript (nazwa = folder)."""
    result = {}
    for studio_prefix, rel in nodes.items():
        base = os.path.normpath(os.path.join(repo_root, rel))
        if not os.path.isdir(base):
            continue
        for dirpath, _dirs, files in os.walk(base):
            for fn in files:
                if not fn.endswith(".luau"):
                    continue
                if fn.endswith(".server.luau") or fn.endswith(".client.luau"):
                    continue  # Script / LocalScript — nie ModuleScript
                abs_path = os.path.join(dirpath, fn)
                rel_dir = os.path.relpath(dirpath, base).replace("\\", "/")
                if fn == "init.luau":
                    sub = rel_dir  # folder staje sie ModuleScript
                else:
                    stem = fn[:-5]  # bez .luau
                    sub = stem if rel_dir in (".", "") else rel_dir + "/" + stem
                if sub in (".", ""):
                    # init.luau w samym katalogu wezla -> modul == wezel
                    studio = studio_prefix
                else:
                    studio = studio_prefix + "." + sub.replace("/", ".")
                result[studio] = abs_path
    return result


# ── zrodlo Studio ─────────────────────────────────────────────────────────────────
def fetch_studio_from_file(path: str):
    data = sys.stdin.read() if path == "-" else open(path, "r", encoding="utf-8-sig").read()
    obj = json.loads(data)
    if isinstance(obj, dict):  # opakowanie {ok, result} z huba/Invoke-Studio
        if not obj.get("ok", True):
            raise RuntimeError("wynik Studio ok=false: " + str(obj.get("error")))
        obj = obj.get("result", obj)
        if isinstance(obj, str):
            obj = json.loads(obj)
    if not isinstance(obj, list):
        raise RuntimeError("oczekiwano tablicy JSON wierszy, dostalem " + type(obj).__name__)
    return obj


def fetch_studio_from_bridge(job_path: str, host="127.0.0.1", port=9977, timeout=320):
    code = open(job_path, "r", encoding="utf-8-sig").read()
    body = json.dumps({"code": code}).encode("utf-8")
    req = urllib.request.Request(
        f"http://{host}:{port}/submit", data=body,
        headers={"Content-Type": "application/json; charset=utf-8"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        d = json.loads(resp.read().decode("utf-8"))
    if not d.get("ok"):
        raise RuntimeError("bridge :9977 blad: " + str(d.get("error")))
    result = d.get("result")
    return json.loads(result) if isinstance(result, str) else result


# ── porownanie ────────────────────────────────────────────────────────────────────
def main():
    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(here)  # tools/ -> repo root (rng)
    ap = argparse.ArgumentParser(description="Walidator modulow: Studio vs dysk (bramka po pushu).")
    ap.add_argument("--project", default=os.path.join(repo_root, "default.project.json"))
    ap.add_argument("--repo-root", default=repo_root)
    ap.add_argument("--studio-json", default=None,
                    help="plik / '-' (stdin) z wynikiem joba; brak = wolaj hub :9977")
    ap.add_argument("--job", default=os.path.join(here, "validate_modules.luau"),
                    help="sciezka joba Luau (tryb bridge)")
    args = ap.parse_args()

    with open(args.project, "r", encoding="utf-8-sig") as f:
        project = json.load(f)
    nodes = collect_mapped_nodes(project)

    try:
        if args.studio_json:
            studio_rows = fetch_studio_from_file(args.studio_json)
        else:
            studio_rows = fetch_studio_from_bridge(args.job)
    except Exception as e:
        print("[FAIL] nie udalo sie pobrac wyniku ze Studio: " + str(e), file=sys.stderr)
        return 3

    studio = {r["path"]: r for r in studio_rows}
    disk_files = disk_modules(args.repo_root, nodes)
    disk = {p: analyze_source(open(fp, "r", encoding="utf-8-sig").read())
            for p, fp in disk_files.items()}

    errors = []  # (kategoria, komunikat)
    all_paths = sorted(set(studio) | set(disk))
    for p in all_paths:
        s = studio.get(p)
        d = disk.get(p)
        if s and not d:
            errors.append(("BRAK PLIKU", f"{p}: jest w Studio, brak na dysku"))
            continue
        if d and not s:
            errors.append(("BRAK PLIKU", f"{p}: jest na dysku, brak w Studio"))
            continue
        # oba istnieja
        if not s.get("tailOk", True):
            errors.append(("BRAK RETURNU", f"{p} [Studio]: ostatnia znaczaca linia = {s.get('tailLast')!r}"))
        if not d.get("tailOk", True):
            errors.append(("BRAK RETURNU", f"{p} [dysk]: ostatnia znaczaca linia = {d.get('tailLast')!r}"))
        if s.get("sha256") != d.get("sha256"):
            diff = d["lineCount"] - s["lineCount"]
            sign = f"+{diff}" if diff > 0 else str(diff)
            errors.append((
                "ROZJECHANIE",
                f"{p}: sha256 rozny (Studio {s['lineCount']} lin / dysk {d['lineCount']} lin, dysk-Studio={sign})",
            ))

    if not errors:
        print(f"OK: {len(disk)} modulow zgodnych (Studio == dysk)")
        return 0

    order = {"BRAK RETURNU": 0, "ROZJECHANIE": 1, "BRAK PLIKU": 2}
    errors.sort(key=lambda e: (order.get(e[0], 9), e[1]))
    print(f"[FAIL] {len(errors)} problem(ow) Studio vs dysk:", file=sys.stderr)
    for cat, msg in errors:
        print(f"  {cat:12} {msg}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
