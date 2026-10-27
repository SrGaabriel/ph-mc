# ph-mc — Purdue Hackers Minecraft distribution

Goal: a player visits one URL, downloads one thing for their OS, logs in with Microsoft once, presses Play, and lands on the club server. After that, every launch updates itself. The players are on macOS, Windows, Linux, and NixOS (NixOS is the trickiest target).

This repo covers distribution and automation. Until `pack/` is imported, mod selection happens in the Prism instance; after that, `pack/` is the source of truth. Don't add or remove mods unless the user asks.

## Dev environment

`.envrc` runs `use flake` (direnv plus nix-direnv), which provides packwiz, just, python3, rsync, curl, zip and unzip. Without direnv, or from a non-interactive shell, use `nix develop --command just <recipe>`. `just` with no arguments lists the recipes.

## Source of truth (current state, 2026-10-27)

- **Client instance:** `~/.local/share/PrismLauncher/instances/Purdue Hackers` (NeoForge 21.1.265, MC 1.21.1, Java 21, 5 GB instance memory override). 125 active jars. Disabled jars end in `.disabled`.
- **Server staging:** `~/ph-server/` (mods, config, defaultconfigs, kubejs). 117 jars.
- **Server:** `gabriel@server.purduehackers.com:/proj/minecraft/server`. Players connect via `phack.sh:25565`. Simple Voice Chat uses UDP 24454. Hardware: Rocky Linux 9, Xeon X5650 (2010, weak single-thread), 32 GB RAM, `-Xmx8G -Xms4G`. The user has no sudo there, and Claude has no SSH access, so the user runs the remote steps.
- **Client-only jars** (keep off the server): sodium, iris, dynamic-fps, entityculling, ImmediatelyFast, MouseTweaks, entity_model_features, entity_texture_features, colorfulhearts, fancymenu, melody, konkrete.
- **Server-only jars** (live only in staging, not in the client): structure_layout_optimizer, async-locator-refined, Chunky, ChunkyBorder.
- **Resource packs** are force-loaded by **Paxi**: `minecraft/config/paxi/resourcepacks/*.zip` plus `resourcepack_load_order.json` (`{"loadOrder": [...]}`, lowest priority first). The built-in mod packs (Meadow betterleaves and connectedtexturesupport, `supplementaries:darker_ropes`) can only be enabled through `options.txt`.
- **Worldgen:** Terralith + Oh The Biomes We've Gone, with Biolith 3.0.14 resolving their feature-order cycle at runtime. A static check still reports the cycle; that's expected.
- **ServerCore** (staging config): `prevent-moving-into-unloaded-chunks: true`, `dynamic.enabled: true`.
- **Pending on the server:** push the latest staging, reset the world (biome and mod changes), then pre-generate with Chunky (radius about 2000, depending on disk; check `df -h`), then `chunky border add`.

The current manual staging and push commands (nu) are below. The CI should replace them.

```nu
let client = $"($env.HOME)/.local/share/PrismLauncher/instances/Purdue Hackers/minecraft/mods/"
let staging = $"($env.HOME)/ph-server/mods/"
(rsync -av --delete
  "--exclude=sodium-*" "--exclude=iris-*" "--exclude=dynamic-fps-*"
  "--exclude=entityculling-*" "--exclude=ImmediatelyFast-*" "--exclude=MouseTweaks-*"
  "--exclude=entity_model_features-*" "--exclude=entity_texture_features-*"
  "--exclude=colorfulhearts-*" "--exclude=fancymenu_*"
  "--exclude=melody_*" "--exclude=konkrete_*"
  "--exclude=structure_layout_optimizer-*" "--exclude=async-locator-refined-*"
  "--exclude=Chunky-*" "--exclude=ChunkyBorder-*"
  "--include=*.jar" "--exclude=*"
  $client $staging)
let remote = "gabriel@server.purduehackers.com:/proj/minecraft/server"
rsync -avz --delete --progress $"($env.HOME)/ph-server/mods/" $"($remote)/mods/"
```

Only use `--delete` on `mods/`. Never use it on the whole server directory, because the local staging copy has no world, libraries, or server jar.

## Architecture

Repo: `srgaabriel/ph-mc` (personal for now). Site and pack are served at **`https://minecraft.phack.sh`**; the Minecraft server address is **`phack.sh`**.

Layout: `pack/` (packwiz), `launcher/` (Prism data-dir template, per-OS wrappers, `run.sh`, `SHA256SUMS`), `site/index.html`, `scripts/`, `flake.nix`, `justfile`, `.github/workflows/`. **All logic lives in just recipes.** Workflows only call `just <recipe>`, so everything also runs locally.

1. **packwiz pack** (`pack/`) is the source of truth.
   - 129 mods. 125 come from Modrinth; 4 are CurseForge-only (ars_technica, ftb-library, ftb-teams, ftb-ultimine) and use `mode = "metadata:curseforge"`. Each `.pw.toml` sets `side` from the lists above.
   - Also holds `config/`, `defaultconfigs/`, `kubejs/` (Paxi packs live in `config/paxi/`). `config/servercore/` holds the server-tuned ServerCore config and is never overwritten by imports.
   - `options.txt` (render 10, sim 8, 90 FPS cap, built-in mod packs enabled, onboarding screens skipped) and `servers.dat` (the `phack.sh` entry, written by `scripts/servers_dat.py`) are marked `preserve = true` in `index.toml`. They're installed once and never overwritten, so players keep their own settings. `packwiz refresh` keeps the flag.
   - `just import-instance` regenerates mods (Modrinth hash lookup, then `packwiz curseforge detect`) and syncs config/defaultconfigs/kubejs from the Prism instance, minus `scripts/config-excludes.txt` (per-user state).
2. **Pack hosting:** `https://minecraft.phack.sh/pack/pack.toml` is baked into every client. Never change it. Upload the pack from the latest release tag, not from `main`.
3. **Self-updating client:** the template instance (`launcher/template/`) has `PreLaunchCommand="$INST_JAVA" -jar packwiz-installer-bootstrap.jar <pack url>` (runs in `minecraft/`), auto-join `phack.sh`, 5 GB max, and `AutomaticJava=true`. Prism (11.1.1) downloads Java 21 itself before the pre-launch step. `prismlauncher.cfg` presets language, theme and auto-Java so the setup wizard only asks for the Microsoft login.
4. **Self-updating server (not built yet):** the start script will run `packwiz-installer-bootstrap -g -s server` before launching, so a deploy is just a restart. That replaces the rsync staging above. The user restarts by hand after each release; NeoForge rejects mismatched shared mods, so client/server skew lasts until that restart.
5. **Per-OS downloads**, built by `release.yml` on a `v*` tag and attached to the GitHub Release. The page links to `releases/latest/download/<file>`:
   - `ph-mc-windows.zip`: Prism **MinGW** portable build (no MSVC runtime needed) with the template in its portable data dir.
   - `ph-mc-macos.dmg`: `Purdue Hackers Minecraft.app`, a wrapper whose shell-script executable runs `run.sh` against the nested, unmodified `Prism Launcher.app` with `--dir ~/Library/Application Support/PurdueHackersMinecraft` (Prism has no portable mode on macOS). It's unsigned, so first launch needs System Settings → Privacy & Security → Open Anyway. Don't re-sign the nested Prism app. The `.dmg` needs `hdiutil`, so it's built on the macOS runner only.
   - `ph-mc-linux.tar.gz`: Prism's Qt6 portable tarball plus `./ph-mc`, which keeps data in `~/.local/share/ph-mc`.
   - **NixOS:** `nix run github:srgaabriel/ph-mc` (flake `packages.default`, Linux only). It wraps nixpkgs `prismlauncher` and pins `jdk21` via `PH_JAVA`, because downloaded JREs can't run on NixOS.
   - `ph-mc-site.tar.gz`: the site plus `pack/`, ready to upload to minecraft.phack.sh.
   - **No `.mrpack`:** the format can't reference CurseForge downloads, and the CurseForge mods' licenses forbid bundling them.
   - `launcher/run.sh` is shared by macOS, Linux and NixOS: it seeds the data dir on first run, always refreshes the bootstrap jar, and applies `PH_JAVA`.
   - Prism and bootstrap versions are pinned in the justfile and verified against `launcher/SHA256SUMS`. When bumping them, update both, plus the bootstrap hash in `flake.nix`.
6. **Download page** (`site/index.html`, plain HTML, pixel-art Minecraft theme). `REPO` and `ADDRESS` consts are at the top of its script. Live status comes from `api.mcsrvstat.us`.

**Release flow:** `just release 0.2.0` bumps `pack.toml`, commits and tags. The user pushes with `git push --follow-tags`. CI builds the downloads. The user uploads `ph-mc-site.tar.gz` contents to minecraft.phack.sh, then restarts the server.

**Deployment is manual and done by the user** (site upload and server restarts). CI never SSHes anywhere, because runners can't reach the server. CI builds artifacts and Releases only; `check.yml` verifies the pack index is fresh and runs `nix flake check`.

## Not yet verified on real hardware

The Windows zip and macOS app haven't been launched on Windows or a Mac yet. The pre-launch quoting in `instance.cfg` hasn't been confirmed by a real Prism launch either.
