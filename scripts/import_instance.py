"""Generate packwiz .pw.toml metafiles from the Prism instance and server staging jars.

Jars are resolved on Modrinth by SHA-1. Sides come from the lists in CLAUDE.md.
Jars not on Modrinth are copied into pack/mods for `packwiz curseforge detect` to resolve.
Usage: python3 scripts/import_instance.py <client-mods-dir> <server-mods-dir> <pack-dir> [--check]
"""

import hashlib
import json
import pathlib
import shutil
import sys
import urllib.parse
import urllib.request

CLIENT_ONLY = [
    "sodium-",
    "iris-",
    "dynamic-fps-",
    "entityculling-",
    "ImmediatelyFast-",
    "MouseTweaks-",
    "entity_model_features-",
    "entity_texture_features-",
    "colorfulhearts-",
    "fancymenu_",
    "melody_",
    "konkrete_",
]
SERVER_ONLY = [
    "structure_layout_optimizer-",
    "async-locator-refined-",
    "Chunky-",
    "ChunkyBorder-",
]
API = "https://api.modrinth.com/v2"
UA = {
    "User-Agent": "purduehackers/ph-mc (pack import)",
    "Content-Type": "application/json",
}


def api(path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, headers=UA)
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def side_of(name):
    if any(name.startswith(p) for p in CLIENT_ONLY):
        return "client"
    if any(name.startswith(p) for p in SERVER_ONLY):
        return "server"
    return "both"


def toml_str(s):
    # JSON escaping is valid TOML basic-string escaping once non-ASCII stays literal
    return json.dumps(s, ensure_ascii=False)


def main():
    client, server, pack = (pathlib.Path(a) for a in sys.argv[1:4])
    check = "--check" in sys.argv
    jars = {p.name: p for p in sorted(client.glob("*.jar"))}
    for p in sorted(server.glob("*.jar")):
        if side_of(p.name) == "server":
            jars.setdefault(p.name, p)

    sha1 = {name: hashlib.sha1(p.read_bytes()).hexdigest() for name, p in jars.items()}
    versions = api(
        "/version_files", {"hashes": list(sha1.values()), "algorithm": "sha1"}
    )
    missing = [n for n, h in sha1.items() if h not in versions]

    project_ids = sorted({v["project_id"] for v in versions.values()})
    projects = {
        p["id"]: p
        for p in api("/projects?ids=" + urllib.parse.quote(json.dumps(project_ids)))
    }

    print(f"{len(jars)} jars, {len(versions)} resolved, {len(missing)} missing")
    for n in missing:
        print("  MISSING:", n)
    if check:
        return 1 if missing else 0

    out = pack / "mods"
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.pw.toml"):  # start clean so mods removed from the instance drop out
        old.unlink()
    for name, h in sha1.items():
        v = versions.get(h)
        if not v:
            shutil.copy2(jars[name], out / name)
            continue
        f = next(f for f in v["files"] if f["hashes"]["sha1"] == h)
        proj = projects[v["project_id"]]
        (out / f"{proj['slug']}.pw.toml").write_text(
            f"name = {toml_str(proj['title'])}\n"
            f"filename = {toml_str(f['filename'])}\n"
            f"side = {toml_str(side_of(name))}\n\n"
            "[download]\n"
            f"url = {toml_str(f['url'])}\n"
            'hash-format = "sha512"\n'
            f"hash = {toml_str(f['hashes']['sha512'])}\n\n"
            "[update]\n[update.modrinth]\n"
            f"mod-id = {toml_str(v['project_id'])}\n"
            f"version = {toml_str(v['id'])}\n",
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
