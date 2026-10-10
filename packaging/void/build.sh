#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Antonio Salsi
#
# build.sh - builds the borgreplay Void Linux package with xbps-create
#
# Usage (as a normal user, from anywhere):   packaging/void/build.sh
#
# Writes the package and a local repository index to dist/. Install with:
#   sudo xbps-install --repository "$PWD/dist" borgreplay

set -e

VERSION="1.0"
REVISION="2"
PKGVER="borgreplay-${VERSION}_${REVISION}"

TOP="$(cd "$(dirname "$0")/../.." && pwd)"
DIST="$TOP/dist"
DESTDIR="$(mktemp -d)"
trap 'rm -rf "$DESTDIR"' EXIT

cd "$TOP"

install -Dm755 bin/borgreplay-cycle        "$DESTDIR/usr/bin/borgreplay-cycle"
install -Dm755 bin/borgreplay-check        "$DESTDIR/usr/bin/borgreplay-check"
install -Dm755 sv/borgreplay-cycle/run     "$DESTDIR/etc/sv/borgreplay-cycle/run"
install -Dm644 cron.d/borgreplay-check     "$DESTDIR/etc/cron.d/borgreplay-check"
install -Dm644 packaging/void/borgreplay-cycle.conf "$DESTDIR/etc/borgreplay-cycle.conf"
# Site settings: the template with every value commented out
sed 's/^\([A-Z_]*=\)/#\1/' .env.sample > "$DESTDIR/etc/borgreplay.env"
chmod 644 "$DESTDIR/etc/borgreplay.env"

DOC="$DESTDIR/usr/share/doc/borgreplay"
install -Dm644 README.md                     "$DOC/README.md"
install -Dm644 README_IT.md                  "$DOC/README_IT.md"
install -Dm755 client/bck_sync_to_borgreplay "$DOC/client/bck_sync_to_borgreplay"
install -Dm644 client/crontab-root           "$DOC/client/crontab-root"

install -Dm644 LICENSE "$DESTDIR/usr/share/licenses/borgreplay/LICENSE"
install -m644 packaging/void/INSTALL.msg "$DESTDIR/INSTALL.msg"

mkdir -p "$DIST"
rm -f "$DIST/$PKGVER.noarch.xbps"
cd "$DIST"
xbps-create \
    -A noarch \
    -n "$PKGVER" \
    -s "Daily wake / Borg replica / check / suspend cycle" \
    -S "Keeps a Borg replica server suspended to RAM, wakes it every night
through the RTC to receive the replica, runs health checks with mail
notification and suspends it again." \
    -D "util-linux>=0 procps-ng>=0 zfs>=0 smartmontools>=0 postfix>=0 cronie>=0" \
    -F "/etc/borgreplay-cycle.conf /etc/borgreplay.env" \
    -l "GPL-2.0-only" \
    "$DESTDIR"
xbps-rindex -a "$DIST/$PKGVER.noarch.xbps"

echo "built $DIST/$PKGVER.noarch.xbps"
