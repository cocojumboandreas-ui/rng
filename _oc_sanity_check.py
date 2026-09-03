#!/usr/bin/env python3
# Jednorazowy sanity-check klucza ROBLOX_OC_KEY_RNG: minimalny create-z-plikiem
# na grupe 664399796. NIE loguje tresci klucza. Uzywa tylko os.environ (odczyt
# w procesie ktory go dostal na wejsciu -- patrz wolanie z PowerShella obok).
import base64, json, os, sys, time
import urllib.request, urllib.error

GROUP_ID = 664399796
KEY = os.environ.get("ROBLOX_OC_KEY_RNG", "")

# najmniejszy poprawny PNG 1x1 pixel (67 bajtow), zakodowany base64 zeby nie
# trzymac binarki w repo jako osobny plik
PNG_1PX_B64 = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk"
    "YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)

def main():
    if not KEY:
        print(json.dumps({"ok": False, "error": "ROBLOX_OC_KEY_RNG puste w tym procesie"}))
        sys.exit(1)

    png_bytes = base64.b64decode(PNG_1PX_B64)
    req = {
        "assetType": "Image",
        "displayName": "sanity_check_DELETE_ME",
        "description": "one-off sanity check, delete manually",
        "creationContext": {"creator": {"groupId": GROUP_ID}},
    }

    boundary = "----ocsanity" + str(int(time.time()))
    body = bytearray()

    def add_field(name, content, content_type=None, filename=None):
        body.extend(f"--{boundary}\r\n".encode())
        if filename:
            body.extend(f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'.encode())
        else:
            body.extend(f'Content-Disposition: form-data; name="{name}"\r\n'.encode())
        if content_type:
            body.extend(f"Content-Type: {content_type}\r\n".encode())
        body.extend(b"\r\n")
        body.extend(content if isinstance(content, (bytes, bytearray)) else content.encode())
        body.extend(b"\r\n")

    add_field("request", json.dumps(req), "application/json")
    add_field("fileContent", png_bytes, "image/png", filename="sanity_check.png")
    body.extend(f"--{boundary}--\r\n".encode())

    url = "https://apis.roblox.com/assets/v1/assets"
    r = urllib.request.Request(url, data=bytes(body), method="POST", headers={
        "x-api-key": KEY,
        "Content-Type": f"multipart/form-data; boundary={boundary}",
    })
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            status = resp.status
            payload = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        status = e.code
        try:
            payload = json.loads(e.read().decode())
        except Exception:
            payload = {"raw": str(e)}
        print(json.dumps({"ok": False, "status": status, "payload": payload}))
        return

    op_path = payload.get("path")
    if not op_path:
        print(json.dumps({"ok": False, "status": status, "payload": payload}))
        return

    op_url = "https://apis.roblox.com/assets/v1/" + op_path
    asset_id = None
    creator_group = None
    deadline = time.time() + 60
    last = None
    while time.time() < deadline:
        gr = urllib.request.Request(op_url, headers={"x-api-key": KEY})
        try:
            with urllib.request.urlopen(gr, timeout=30) as gresp:
                last = json.loads(gresp.read().decode())
        except urllib.error.HTTPError as e:
            try:
                last = json.loads(e.read().decode())
            except Exception:
                last = {"raw": str(e)}
            print(json.dumps({"ok": False, "status": e.code, "payload": last}))
            return
        if last.get("done"):
            resp_obj = last.get("response") or {}
            asset_id = resp_obj.get("assetId")
            break
        time.sleep(1.5)

    print(json.dumps({
        "ok": asset_id is not None,
        "assetId": asset_id,
        "raw_operation": last,
    }))

if __name__ == "__main__":
    main()
