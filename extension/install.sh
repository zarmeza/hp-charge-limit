#!/usr/bin/env bash
# Install the optional GNOME Shell indicator for the current desktop user.
# Do not run this with sudo.
set -euo pipefail
cd "$(dirname "$0")"

UUID=hp-charge-limit@zarmeza
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
DEST="$DATA_HOME/gnome-shell/extensions/$UUID"

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo "Run this as your desktop user, not with sudo." >&2
    exit 1
fi

if ! command -v gnome-extensions >/dev/null 2>&1; then
    echo "gnome-extensions is not installed." >&2
    exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

install -m 0644 metadata.json extension.js "$tmpdir/"
(
    cd "$tmpdir"
    zip -q "$UUID.shell-extension.zip" metadata.json extension.js
)

gnome-extensions install --force "$tmpdir/$UUID.shell-extension.zip"

if [[ ! -f $DEST/metadata.json || ! -f $DEST/extension.js ]]; then
    echo "Installation did not create $DEST." >&2
    exit 1
fi

if gnome-extensions enable "$UUID" 2>/dev/null; then
    if gnome-extensions info "$UUID" 2>/dev/null | grep -q 'State: ACTIVE'; then
        echo "Enabled $UUID."
    else
        echo "Installed and enabled $UUID."
        echo "The running shell has not loaded it yet; log out and back in to activate it."
    fi
else
    # The running shell only scans extension directories at startup. Queue the
    # extension in GSettings so it loads on the next login.
    current=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "[]")
    if [[ $current != *"'$UUID'"* ]]; then
        case $current in
            "[]"|"@as []") current="['$UUID']" ;;
            *) current="${current%]}, '$UUID']" ;;
        esac
        gsettings set org.gnome.shell enabled-extensions "$current"
    fi
    echo "Installed and queued $UUID for your next login."
    echo "Log out and back in to activate it."
fi

echo
echo "The daemon still enforces the cap; this extension only changes the indicator."
echo "Remove it with: $PWD/uninstall.sh"
