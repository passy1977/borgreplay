#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Antonio Salsi
#
# install.sh - installs borgreplay-cycle and borgreplay-check (Void Linux, runit)
#
# Usage (as root):   ./install.sh
#
# Site settings are taken from .env (see .env.sample) and installed as
# /etc/borgreplay/borgreplay.env. An existing /etc/borgreplay/cycle.conf is not overwritten.

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "install.sh: must be run as root" >&2
    exit 2
fi

cd "$(dirname "$0")"

if [ ! -r .env ]; then
    echo "install.sh: .env missing, copy .env.sample to .env and fill it in" >&2
    exit 2
fi

install -d -m 755 /etc/borgreplay

# Files of the versions before /etc/borgreplay/: the old site settings are
# replaced by .env, the cycle settings and the stay-awake flag are moved
rm -f /etc/borgreplay.env
[ -e /etc/borgreplay-cycle.conf ] && [ ! -e /etc/borgreplay/cycle.conf ] &&
    mv /etc/borgreplay-cycle.conf /etc/borgreplay/cycle.conf
[ -e /etc/borgreplay-stay-awake ] && mv /etc/borgreplay-stay-awake /etc/borgreplay/stay-awake

install -m 644 .env /etc/borgreplay/borgreplay.env

install -m 755 bin/borgreplay-cycle /usr/local/bin/borgreplay-cycle
install -m 755 bin/borgreplay-check /usr/local/bin/borgreplay-check

install -d -m 755 /etc/sv/borgreplay-cycle
install -m 755 sv/borgreplay-cycle/run /etc/sv/borgreplay-cycle/run

install -m 644 cron.d/borgreplay-check /etc/cron.d/borgreplay-check

if [ ! -e /etc/borgreplay/cycle.conf ]; then
    install -m 644 etc/cycle.conf /etc/borgreplay/cycle.conf
else
    echo "leaving /etc/borgreplay/cycle.conf unchanged"
fi

if [ ! -e /var/service/borgreplay-cycle ]; then
    ln -s /etc/sv/borgreplay-cycle /var/service/
    echo "borgreplay-cycle service enabled"
else
    sv restart borgreplay-cycle
    echo "borgreplay-cycle service restarted"
fi
