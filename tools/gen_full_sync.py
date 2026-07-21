#!/usr/bin/env python3
"""Generate a StudioBridge push job that syncs ALL of src/ -> the open Studio place.

The output .luau is non-destructive (create/update named nodes only) and matches the
partial-node mapping in default.project.json, so it never touches Studio-owned assets
(RNG_MAP, ReplicatedStorage.Assets, ...). It is a GENERATED artifact (embeds every
source file) — regenerate it after any src change instead of committing it.

Usage:
    python tools/gen_full_sync.py [OUT.luau]      # default: ./push_full_sync.luau
    # then, with StudioBridge hub running (from D:\\RobloxProjects):
    #   .\\Invoke-Studio.ps1 -File OUT.luau
"""
import os
import sys
import glob

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "src"))


def rd(p):
    return open(p, encoding="utf-8").read()


def emb(s):
    # pick a long-bracket level that doesn't collide with the source
    n = 0
    while ("]" + "=" * n + "]") in s or ("[" + "=" * n + "[") in s:
        n += 1
    eq = "=" * n
    return f"[{eq}[\n{s}]{eq}]"


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.getcwd(), "push_full_sync.luau")
    L = []
    L.append("--!nocheck")
    L.append("-- FULL SYNC src/ -> Studio (plac edit == dysk). GENEROWANE przez tools/gen_full_sync.py.")
    L.append("-- Non-destructive: tylko create/update nazwanych wezlow (nie rusza Studio-owned assetow).")
    L.append("local RS=game:GetService('ReplicatedStorage')")
    L.append("local SSS=game:GetService('ServerScriptService')")
    L.append("local SPS=game:GetService('StarterPlayer'):WaitForChild('StarterPlayerScripts')")
    L.append("""local function ef(parent,name)
  local e=parent:FindFirstChild(name)
  if e and not e:IsA('Folder') then e:Destroy(); e=nil end
  if not e then e=Instance.new('Folder'); e.Name=name; e.Parent=parent end
  return e
end""")
    L.append("""local function es(parent,name,class,src)
  local e=parent:FindFirstChild(name)
  if e and e.ClassName~=class then e:Destroy(); e=nil end
  if not e then e=Instance.new(class); e.Name=name; e.Parent=parent end
  e.Source=src
  return e
end""")
    L.append("local pushed=0")

    def push(var_parent, name, cls, path):
        L.append(f"es({var_parent},'{name}','{cls}',{emb(rd(path))}); pushed+=1")

    # RS.Framework/*  (ModuleScripts)
    L.append("local fw=ef(RS,'Framework')")
    for f in sorted(glob.glob(os.path.join(SRC, "ReplicatedStorage", "Framework", "*.luau"))):
        push("fw", os.path.splitext(os.path.basename(f))[0], "ModuleScript", f)

    # RS.Content.Config/*  (ModuleScripts)
    L.append("local content=ef(RS,'Content'); local config=ef(content,'Config')")
    for f in sorted(glob.glob(os.path.join(SRC, "ReplicatedStorage", "Content", "Config", "*.luau"))):
        push("config", os.path.splitext(os.path.basename(f))[0], "ModuleScript", f)

    # RS.Shared/*  (ModuleScripts)
    L.append("local shared=ef(RS,'Shared')")
    for f in sorted(glob.glob(os.path.join(SRC, "ReplicatedStorage", "Shared", "*.luau"))):
        push("shared", os.path.splitext(os.path.basename(f))[0], "ModuleScript", f)

    # SSS.init  (Script from init/init.server.luau — folderized)
    push("SSS", "init", "Script", os.path.join(SRC, "ServerScriptService", "init", "init.server.luau"))

    # SSS.Services/*  (ModuleScripts)
    L.append("local services=ef(SSS,'Services')")
    for f in sorted(glob.glob(os.path.join(SRC, "ServerScriptService", "Services", "*.luau"))):
        push("services", os.path.splitext(os.path.basename(f))[0], "ModuleScript", f)

    # SSS.Server.Vendor.ProfileStore  (ModuleScript from Server/Vendor/ProfileStore/init.luau)
    L.append("local server=ef(SSS,'Server'); local vendor=ef(server,'Vendor')")
    push("vendor", "ProfileStore", "ModuleScript", os.path.join(SRC, "ServerScriptService", "Server", "Vendor", "ProfileStore", "init.luau"))

    # SPS.init  (LocalScript from init/init.client.luau — folderized)
    push("SPS", "init", "LocalScript", os.path.join(SRC, "StarterPlayer", "StarterPlayerScripts", "init", "init.client.luau"))

    # SPS.Controllers/*  (ModuleScripts)
    L.append("local controllers=ef(SPS,'Controllers')")
    for f in sorted(glob.glob(os.path.join(SRC, "StarterPlayer", "StarterPlayerScripts", "Controllers", "*.luau"))):
        push("controllers", os.path.splitext(os.path.basename(f))[0], "ModuleScript", f)

    L.append("return { pushed = pushed }")

    job = "\n".join(L) + "\n"
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(job)
    print(f"wrote {out_path} ({len(job)} bytes)")


if __name__ == "__main__":
    main()
