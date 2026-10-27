set shell := ["bash", "-euo", "pipefail", "-c"]

freesm := "2.3.1"
bootstrap := "v0.0.3"
instance := env("HOME") / ".local/share/PrismLauncher/instances/Purdue Hackers/minecraft"
staging := env("HOME") / "ph-server"
cache := "build/cache"
dist := "build/dist"

default:
    @just --list

# Regenerate pack/ from the Prism instance: mods (Modrinth, CurseForge fallback), config, defaultconfigs, kubejs
import-instance:
    python3 -I scripts/import_instance.py "{{instance}}/mods" "{{staging}}/mods" pack
    rsync -a --delete --exclude-from=scripts/config-excludes.txt \
      --include='config/***' --include='defaultconfigs/***' --include='kubejs/***' --exclude='*' \
      "{{instance}}/" pack/
    cd pack && packwiz curseforge detect && packwiz refresh

# Rebuild pack/index.toml after editing files in pack/
refresh:
    cd pack && packwiz refresh

# Fail if pack/index.toml is stale
check:
    cd pack && packwiz refresh
    git diff --exit-code -- pack

# Download pinned Freesm Launcher builds and the packwiz bootstrap, verified against launcher/SHA256SUMS
fetch:
    mkdir -p {{cache}}
    cd {{cache}} && for f in \
      FreesmLauncher-Windows-MinGW-w64-Portable-{{freesm}}.zip \
      FreesmLauncher-Linux-Qt6-Portable-{{freesm}}.tar.gz \
      FreesmLauncher-macOS-{{freesm}}.zip; do \
        [ -f "$f" ] || curl -fsSLO "https://github.com/FreesmTeam/FreesmLauncher/releases/download/{{freesm}}/$f"; \
      done
    cd {{cache}} && { [ -f packwiz-installer-bootstrap.jar ] || curl -fsSLO \
      "https://github.com/packwiz/packwiz-installer-bootstrap/releases/download/{{bootstrap}}/packwiz-installer-bootstrap.jar"; }
    cd {{cache}} && sha256sum -c ../../launcher/SHA256SUMS

# Assemble the launcher data-dir template (settings + instance + bootstrap jar)
template: fetch
    rm -rf build/template
    cp -R launcher/template build/template
    rm -f "build/template/instances/Purdue Hackers/minecraft/.gitkeep"
    cp {{cache}}/packwiz-installer-bootstrap.jar "build/template/instances/Purdue Hackers/minecraft/"

# Portable Freesm (MinGW build, no MSVC runtime needed) with the instance preinstalled
package-windows: template
    rm -rf build/windows && mkdir -p "build/windows/Purdue Hackers Minecraft" {{dist}}
    unzip -q {{cache}}/FreesmLauncher-Windows-MinGW-w64-Portable-{{freesm}}.zip -d "build/windows/Purdue Hackers Minecraft"
    cp -R build/template/. "build/windows/Purdue Hackers Minecraft/"
    rm -f {{dist}}/ph-mc-windows.zip
    cd build/windows && zip -qr ../../{{dist}}/ph-mc-windows.zip "Purdue Hackers Minecraft"

# Tarball: portable Freesm + template + ./ph-mc wrapper that keeps data in ~/.local/share/ph-mc
package-linux: template
    rm -rf build/linux && mkdir -p build/linux/ph-mc/freesm {{dist}}
    tar xzf {{cache}}/FreesmLauncher-Linux-Qt6-Portable-{{freesm}}.tar.gz -C build/linux/ph-mc/freesm
    rm -f build/linux/ph-mc/freesm/portable.txt
    cp -R build/template build/linux/ph-mc/template
    cp launcher/run.sh launcher/linux/ph-mc build/linux/ph-mc/
    tar czf {{dist}}/ph-mc-linux.tar.gz -C build/linux ph-mc

# Wrapper .app around Freesm Launcher.app; the .dmg step needs macOS (hdiutil)
package-macos: template
    #!/usr/bin/env bash
    set -euo pipefail
    app="build/macos/Purdue Hackers Minecraft.app"
    rm -rf build/macos && mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" {{dist}}
    if command -v ditto >/dev/null; then
      ditto -x -k {{cache}}/FreesmLauncher-macOS-{{freesm}}.zip "$app/Contents/Resources"
      rm -rf "$app/Contents/Resources/__MACOSX"
    else
      unzip -q {{cache}}/FreesmLauncher-macOS-{{freesm}}.zip -x '__MACOSX/*' -d "$app/Contents/Resources"
    fi
    cp launcher/macos/Info.plist "$app/Contents/"
    cp launcher/macos/ph-mc "$app/Contents/MacOS/"
    cp launcher/run.sh "$app/Contents/Resources/"
    cp -R build/template "$app/Contents/Resources/template"
    cp "$app/Contents/Resources/Freesm Launcher.app/Contents/Resources/FreesmLauncher.icns" "$app/Contents/Resources/"
    ln -s /Applications build/macos/Applications
    if command -v hdiutil >/dev/null; then
      hdiutil create -volname "Purdue Hackers Minecraft" -srcfolder build/macos -ov -format UDZO {{dist}}/ph-mc-macos.dmg
    else
      echo "No hdiutil: built $app only. The .dmg is made on macOS (CI)."
    fi

# Bump the pack version, commit, and tag. Pushing the tag builds the downloads and publishes the pack to GitHub Pages.
release version:
    git diff --quiet && git diff --cached --quiet || { echo "Commit or stash your changes first."; exit 1; }
    sed -i.bak 's/^version = .*/version = "{{version}}"/' pack/pack.toml && rm pack/pack.toml.bak
    cd pack && packwiz refresh
    git commit -am "Release {{version}}"
    git tag "v{{version}}"
    @echo "Tagged v{{version}}. Push with: git push --follow-tags"

# Serve pack/ at http://localhost:8080/pack.toml (for try-fresh)
serve:
    cd pack && packwiz serve

# Launch the NixOS build as a brand-new player: empty data dir in build/try, pack from `just serve`
try-fresh:
    rm -rf build/try
    XDG_DATA_HOME="$PWD/build/try" PH_PACK_URL=http://localhost:8080/pack.toml nix run .
