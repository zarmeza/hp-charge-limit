#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Run with: sudo $0" >&2
    exit 1
fi

if ! modinfo acpi_call >/dev/null 2>&1; then
    echo "acpi-call-dkms is not installed." >&2
    echo "Install it first: sudo apt install acpi-call-dkms" >&2
    exit 1
fi

install -m 0755 hp-charge-limit /usr/local/sbin/hp-charge-limit
install -m 0644 hp-charge-limit.service /etc/systemd/system/hp-charge-limit.service
install -m 0644 acpi-call.conf /etc/modules-load.d/acpi-call.conf
install -d -m 0755 /usr/local/share/doc/hp-charge-limit
install -m 0644 README.md /usr/local/share/doc/hp-charge-limit/README.md

systemctl daemon-reload
systemctl enable hp-charge-limit.service
systemctl restart hp-charge-limit.service
sleep 2

systemctl --no-pager --full status hp-charge-limit.service || true
echo
/usr/local/sbin/hp-charge-limit --status || true
echo
echo "Optional desktop indicator: ./extension/install.sh (run as your desktop user, no sudo)"
