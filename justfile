set shell := ["bash", "-euo", "pipefail", "-c"]

prism := "11.1.1"
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

# Download pinned Prism builds and the packwiz bootstrap, verified against launcher/SHA256SUMS
fetch:
    mkdir -p {{cache}}
    cd {{cache}} && for f in \
      PrismLauncher-Windows-MinGW-w64-Portable-{{prism}}.zip \
      PrismLauncher-Linux-Qt6-Portable-{{prism}}.tar.gz \
      PrismLauncher-macOS-{{prism}}.zip; do \
        [ -f "$f" ] || curl -fsSLO "https://github.com/PrismLauncher/PrismLauncher/releases/download/{{prism}}/$f"; \
      done
    cd {{cache}} && { [ -f packwiz-installer-bootstrap.jar ] || curl -fsSLO \
      "https://github.com/packwiz/packwiz-installer-bootstrap/releases/download/{{bootstrap}}/packwiz-installer-bootstrap.jar"; }
    cd {{cache}} && sha256sum -c ../../launcher/SHA256SUMS

# Assemble the Prism data-dir template (settings + instance + bootstrap jar)
template: fetch
    rm -rf build/template
    cp -R launcher/template build/template
    rm -f "build/template/instances/Purdue Hackers/minecraft/.gitkeep"
    cp {{cache}}/packwiz-installer-bootstrap.jar "build/template/instances/Purdue Hackers/minecraft/"

# Portable Prism (MinGW build, no MSVC runtime needed) with the instance preinstalled
package-windows: template
    rm -rf build/windows && mkdir -p "build/windows/Purdue Hackers Minecraft" {{dist}}
    unzip -q {{cache}}/PrismLauncher-Windows-MinGW-w64-Portable-{{prism}}.zip -d "build/windows/Purdue Hackers Minecraft"
    cp -R build/template/. "build/windows/Purdue Hackers Minecraft/"
    rm -f {{dist}}/ph-mc-windows.zip
    cd build/windows && zip -qr ../../{{dist}}/ph-mc-windows.zip "Purdue Hackers Minecraft"

# Tarball: portable Prism + template + ./ph-mc wrapper that keeps data in ~/.local/share/ph-mc
package-linux: template
    rm -rf build/linux && mkdir -p build/linux/ph-mc/prism {{dist}}
    tar xzf {{cache}}/PrismLauncher-Linux-Qt6-Portable-{{prism}}.tar.gz -C build/linux/ph-mc/prism
    rm -f build/linux/ph-mc/prism/portable.txt
    cp -R build/template build/linux/ph-mc/template
    cp launcher/run.sh launcher/linux/ph-mc build/linux/ph-mc/
    tar czf {{dist}}/ph-mc-linux.tar.gz -C build/linux ph-mc

# Wrapper .app around Prism Launcher.app; the .dmg step needs macOS (hdiutil)
package-macos: template
    #!/usr/bin/env bash
    set -euo pipefail
    app="build/macos/Purdue Hackers Minecraft.app"
    rm -rf build/macos && mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" {{dist}}
    if command -v ditto >/dev/null; then
      ditto -x -k {{cache}}/PrismLauncher-macOS-{{prism}}.zip "$app/Contents/Resources"
      rm -rf "$app/Contents/Resources/__MACOSX"
    else
      unzip -q {{cache}}/PrismLauncher-macOS-{{prism}}.zip -x '__MACOSX/*' -d "$app/Contents/Resources"
    fi
    cp launcher/macos/Info.plist "$app/Contents/"
    cp launcher/macos/ph-mc "$app/Contents/MacOS/"
    cp launcher/run.sh "$app/Contents/Resources/"
    cp -R build/template "$app/Contents/Resources/template"
    cp "$app/Contents/Resources/Prism Launcher.app/Contents/Resources/PrismLauncher.icns" "$app/Contents/Resources/"
    ln -s /Applications build/macos/Applications
    if command -v hdiutil >/dev/null; then
      hdiutil create -volname "Purdue Hackers Minecraft" -srcfolder build/macos -ov -format UDZO {{dist}}/ph-mc-macos.dmg
    else
      echo "No hdiutil: built $app only. The .dmg is made on macOS (CI)."
    fi

# Site + pack, ready to upload to minecraft.phack.sh (also archived as ph-mc-site.tar.gz)
build-site:
    rm -rf build/site && mkdir -p build/site {{dist}}
    cp -R site/. build/site/
    cp -R pack build/site/pack
    tar czf {{dist}}/ph-mc-site.tar.gz -C build/site .

# Bump the pack version, commit, and tag. Pushing the tag starts the release build.
release version:
    git diff --quiet && git diff --cached --quiet || { echo "Commit or stash your changes first."; exit 1; }
    sed -i.bak 's/^version = .*/version = "{{version}}"/' pack/pack.toml && rm pack/pack.toml.bak
    cd pack && packwiz refresh
    git commit -am "Release {{version}}"
    git tag "v{{version}}"
    @echo "Tagged v{{version}}. Push with: git push --follow-tags"
