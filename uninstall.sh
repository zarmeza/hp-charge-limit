#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Run with: sudo $0" >&2
    exit 1
fi

systemctl disable --now hp-charge-limit.service 2>/dev/null || true
if [[ -x /usr/local/sbin/hp-charge-limit ]]; then
    /usr/local/sbin/hp-charge-limit --restore || true
fi

rm -f /etc/systemd/system/hp-charge-limit.service \
      /usr/local/sbin/hp-charge-limit \
      /etc/modules-load.d/acpi-call.conf
rm -rf /usr/local/share/doc/hp-charge-limit
systemctl daemon-reload

echo "hp-charge-limit removed; charging restored to auto."
echo "acpi-call-dkms is still installed."
echo
echo "If you installed the optional desktop indicator, remove it as your user:"
echo "  ./extension/uninstall.sh"
