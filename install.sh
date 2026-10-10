#!/bin/sh
#
# install.sh - installa borgreplay-cycle e borgreplay-check (Void Linux, runit)
#
# Uso (come root):   ./install.sh
#
# La configurazione esistente in /etc/borgreplay-cycle.conf non viene sovrascritta.

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "install.sh: va eseguito come root" >&2
    exit 2
fi

cd "$(dirname "$0")"

install -m 755 bin/borgreplay-cycle /usr/local/bin/borgreplay-cycle
install -m 755 bin/borgreplay-check /usr/local/bin/borgreplay-check

install -d -m 755 /etc/sv/borgreplay-cycle
install -m 755 sv/borgreplay-cycle/run /etc/sv/borgreplay-cycle/run

install -m 644 cron.d/borgreplay-check /etc/cron.d/borgreplay-check

if [ ! -e /etc/borgreplay-cycle.conf ]; then
    install -m 644 etc/borgreplay-cycle.conf /etc/borgreplay-cycle.conf
else
    echo "lascio invariato /etc/borgreplay-cycle.conf"
fi

if [ ! -e /var/service/borgreplay-cycle ]; then
    ln -s /etc/sv/borgreplay-cycle /var/service/
    echo "servizio borgreplay-cycle abilitato"
else
    sv restart borgreplay-cycle
    echo "servizio borgreplay-cycle riavviato"
fi
