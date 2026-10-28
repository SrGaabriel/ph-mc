"""Generate packwiz .pw.toml metafiles from the Prism instance and server staging jars.

Jars are resolved on Modrinth by SHA-1. Sides come from the CLIENT_ONLY / SERVER_ONLY lists.
Jars not on Modrinth are copied into pack/mods for `packwiz curseforge detect` to resolve.
Usage: python3 scripts/import_instance.py <client-mods-dir> <server-mods-dir> <pack-dir> [--check]

--paxi replaces Paxi resource/data pack zips under <pack-dir>/config/paxi with Modrinth
metafiles, so we link to them instead of hosting other people's work. Zips not on Modrinth stay.
Usage: python3 scripts/import_instance.py --paxi <pack-dir>
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


def lookup(sha1s):
    """sha1 -> Modrinth version, and project id -> project, for the hashes Modrinth knows."""
    versions = api("/version_files", {"hashes": list(sha1s), "algorithm": "sha1"})
    project_ids = sorted({v["project_id"] for v in versions.values()})
    projects = {
        p["id"]: p
        for p in api("/projects?ids=" + urllib.parse.quote(json.dumps(project_ids)))
    } if project_ids else {}
    return versions, projects


def write_meta(path, title, filename, side, version, h):
    f = next(f for f in version["files"] if f["hashes"]["sha1"] == h)
    path.write_text(
        f"name = {toml_str(title)}\n"
        f"filename = {toml_str(filename)}\n"
        f"side = {toml_str(side)}\n\n"
        "[download]\n"
        f"url = {toml_str(f['url'])}\n"
        'hash-format = "sha512"\n'
        f"hash = {toml_str(f['hashes']['sha512'])}\n\n"
        "[update]\n[update.modrinth]\n"
        f"mod-id = {toml_str(version['project_id'])}\n"
        f"version = {toml_str(version['id'])}\n",
        encoding="utf-8",
    )
    return f


def link_paxi(pack):
    zips = sorted((pack / "config" / "paxi").glob("*/*.zip"))
    sha1 = {z: hashlib.sha1(z.read_bytes()).hexdigest() for z in zips}
    if not sha1:
        return 0
    versions, projects = lookup(sha1.values())
    for z, h in sha1.items():
        v = versions.get(h)
        if not v:
            print("  NOT ON MODRINTH, still bundled:", z)
            continue
        proj = projects[v["project_id"]]
        # Keep the local filename: Paxi's load order lists packs by name
        side = "client" if z.parent.name == "resourcepacks" else "both"
        write_meta(z.parent / f"{proj['slug']}.pw.toml", proj["title"], z.name, side, v, h)
        z.unlink()
    print(f"{len(zips)} Paxi zips, {sum(h in versions for h in sha1.values())} linked to Modrinth")
    return 0


def main():
    if sys.argv[1] == "--paxi":
        return link_paxi(pathlib.Path(sys.argv[2]))
    client, server, pack = (pathlib.Path(a) for a in sys.argv[1:4])
    check = "--check" in sys.argv
    jars = {p.name: p for p in sorted(client.glob("*.jar"))}
    for p in sorted(server.glob("*.jar")):
        if side_of(p.name) == "server":
            jars.setdefault(p.name, p)

    sha1 = {name: hashlib.sha1(p.read_bytes()).hexdigest() for name, p in jars.items()}
    versions, projects = lookup(sha1.values())
    missing = [n for n, h in sha1.items() if h not in versions]

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
        write_meta(out / f"{proj['slug']}.pw.toml", proj["title"], f["filename"], side_of(name), v, h)
    return 0


if __name__ == "__main__":
    sys.exit(main())
