#!/bin/sh
#
# uninstall.sh - removes borgreplay-cycle and borgreplay-check
#
# Usage (as root):   ./uninstall.sh
#
# Leaves /etc/borgreplay-cycle.conf and the state in /var/lib/borgreplay-check in place.

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "uninstall.sh: must be run as root" >&2
    exit 2
fi

if [ -e /var/service/borgreplay-cycle ]; then
    sv down borgreplay-cycle || true
    rm -f /var/service/borgreplay-cycle
fi

rm -rf /etc/sv/borgreplay-cycle
rm -f /etc/cron.d/borgreplay-check
rm -f /usr/local/bin/borgreplay-cycle /usr/local/bin/borgreplay-check

echo "removed; the machine will no longer suspend"
