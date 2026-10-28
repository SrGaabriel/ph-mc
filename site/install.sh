#!/bin/sh
# Purdue Hackers Minecraft installer for macOS and Linux:
#   curl -fsSL https://minecraft.phack.sh/install.sh | sh
# curl doesn't quarantine what it downloads, so Gatekeeper never blocks the unsigned app.
# Running it again updates the launcher and keeps accounts, settings and worlds.
set -eu

releases=https://github.com/srgaabriel/ph-mc/releases/latest/download
name="Purdue Hackers Minecraft"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

install_macos() {
  tmp="$(mktemp -d)"
  trap 'hdiutil detach -quiet "$tmp/mnt" 2>/dev/null; rm -rf "$tmp"' EXIT
  say "Downloading $name..."
  curl -fL --progress-bar "$releases/ph-mc-macos.dmg" -o "$tmp/ph-mc.dmg"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$tmp/mnt" "$tmp/ph-mc.dmg"

  dest=/Applications
  [ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
  rm -rf "$dest/$name.app"
  ditto "$tmp/mnt/$name.app" "$dest/$name.app"

  say "Installed $dest/$name.app. Opening it..."
  say "Hold Option while opening the app to get the launcher window instead of the game."
  open "$dest/$name.app"
}

install_linux() {
  if [ -e /etc/NIXOS ]; then
    say "NixOS detected, this won't run here. Use: nix run github:srgaabriel/ph-mc"
    exit 0
  fi
  [ "$(uname -m)" = x86_64 ] || die "Only x86_64 Linux is supported for now."

  data="${XDG_DATA_HOME:-$HOME/.local/share}"
  app="$data/ph-mc-launcher" # the player's data stays in $data/ph-mc
  bin="$HOME/.local/bin"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  say "Downloading $name..."
  curl -fL --progress-bar "$releases/ph-mc-linux.tar.gz" | tar xz -C "$tmp"
  mkdir -p "$bin" "$data/applications"
  rm -rf "$app"
  mv "$tmp/ph-mc" "$app"

  ln -sf "$app/ph-mc" "$bin/ph-mc"
  cat > "$data/applications/ph-mc.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=Join the Purdue Hackers server
Exec="$app/ph-mc"
Icon=$app/freesm/share/icons/hicolor/256x256/apps/org.freesmlauncher.FreesmLauncher.png
Categories=Game;
Actions=launcher;

[Desktop Action launcher]
Name=Open the launcher
Exec="$app/ph-mc" --launcher
EOF

  say "Installed. Find \"$name\" in your app menu, or run ph-mc (ph-mc --launcher for the launcher window)."
  case ":$PATH:" in
    *":$bin:"*) ;;
    *) say "$bin isn't on your PATH, so the ph-mc command needs the full path: $app/ph-mc" ;;
  esac
  say "Starting the game..."
  nohup "$app/ph-mc" >/dev/null 2>&1 &
}

# Everything above only defines functions, so a cut-off download runs nothing
case "$(uname -s)" in
  Darwin) install_macos ;;
  Linux) install_linux ;;
  *) die "On Windows? Use the PowerShell command from https://minecraft.phack.sh" ;;
esac
