#!/bin/sh
#
# uninstall.sh - rimuove borgreplay-cycle e borgreplay-check
#
# Uso (come root):   ./uninstall.sh
#
# Lascia al loro posto /etc/borgreplay-cycle.conf e lo stato in /var/lib/borgreplay-check.

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "uninstall.sh: va eseguito come root" >&2
    exit 2
fi

if [ -e /var/service/borgreplay-cycle ]; then
    sv down borgreplay-cycle || true
    rm -f /var/service/borgreplay-cycle
fi

rm -rf /etc/sv/borgreplay-cycle
rm -f /etc/cron.d/borgreplay-check
rm -f /usr/local/bin/borgreplay-cycle /usr/local/bin/borgreplay-check

echo "rimosso; la macchina non andra' piu' in sospensione"
