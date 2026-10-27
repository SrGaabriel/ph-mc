#!/usr/bin/env bash
# Seeds a per-user Prism data dir with the Purdue Hackers instance on first run, then starts Prism.
#   PH_PRISM     Prism binary
#   PH_TEMPLATE  dir holding prismlauncher.cfg and instances/
#   PH_DATA      per-user data dir
#   PH_JAVA      optional: pin this Java instead of Prism's auto-download (NixOS can't run downloaded JREs)
set -euo pipefail

inst="$PH_DATA/instances/Purdue Hackers"
mkdir -p "$PH_DATA/instances"

if [ ! -e "$PH_DATA/prismlauncher.cfg" ]; then
  cp "$PH_TEMPLATE/prismlauncher.cfg" "$PH_DATA/"
  chmod u+w "$PH_DATA/prismlauncher.cfg"
fi
if [ ! -d "$inst" ]; then
  cp -R "$PH_TEMPLATE/instances/Purdue Hackers" "$inst"
  chmod -R u+w "$inst"
fi
# Always refresh the bootstrap jar so a new launcher build can ship a new one
cp -f "$PH_TEMPLATE/instances/Purdue Hackers/minecraft/packwiz-installer-bootstrap.jar" "$inst/minecraft/"
chmod u+w "$inst/minecraft/packwiz-installer-bootstrap.jar"

# set_key FILE KEY VALUE: replace KEY in [General], or add it right after the header
set_key() {
  local tmp
  tmp="$(mktemp)"
  awk -v k="$2" -v v="$3" '
    /^\[/ { if (sec == "[General]" && !done) { print k "=" v; done = 1 } sec = $0 }
    sec == "[General]" && index($0, k "=") == 1 { if (!done) print k "=" v; done = 1; next }
    { print }
    END { if (!done) { if (sec != "[General]") print "[General]"; print k "=" v } }
  ' "$1" > "$tmp"
  cat "$tmp" > "$1"
  rm -f "$tmp"
}

if [ -n "${PH_JAVA:-}" ]; then
  set_key "$PH_DATA/prismlauncher.cfg" AutomaticJavaSwitch false
  set_key "$PH_DATA/prismlauncher.cfg" AutomaticJavaDownload false
  set_key "$inst/instance.cfg" AutomaticJava false
  set_key "$inst/instance.cfg" OverrideJavaLocation true
  set_key "$inst/instance.cfg" JavaPath "$PH_JAVA"
fi

exec "$PH_PRISM" --dir "$PH_DATA" "$@"
