#!/usr/bin/env bash
# Remove the optional GNOME Shell indicator for the current desktop user.
# Do not run this with sudo.
set -euo pipefail

UUID=hp-charge-limit@zarmeza
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
DEST="$DATA_HOME/gnome-shell/extensions/$UUID"

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo "Run this as your desktop user, not with sudo." >&2
    exit 1
fi

gnome-extensions disable "$UUID" 2>/dev/null || true
rm -rf "$DEST"

# If the running shell never discovered the extension, it may still be queued
# in GSettings. Drop it so the next session does not try to load a missing path.
if command -v gsettings >/dev/null 2>&1; then
    current=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)
    if [[ $current == *"'$UUID'"* ]] && command -v python3 >/dev/null 2>&1; then
        if updated=$(
            python3 -c '
import ast, sys
uuid = sys.argv[1]
values = [value for value in ast.literal_eval(sys.stdin.read()) if value != uuid]
print("[" + ", ".join(repr(value) for value in values) + "]")
' "$UUID" <<<"$current"
        ); then
            gsettings set org.gnome.shell enabled-extensions "$updated"
        fi
    fi
fi

echo "Removed $UUID. The charge-limit daemon is unchanged."
