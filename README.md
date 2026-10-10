# borgreplay

**English** | [Italiano](README_IT.md)

Daily wake / replica / check / suspend cycle for the Borg replica server
`borgreplay` (Void Linux, runit, ZFS pool `backup`).

The machine spends the day suspended to RAM (S3). Every night it wakes up on its
own through the RTC, receives the Borg replica, runs the health checks, sends
any mail and goes back to sleep until the next night.

## Components

| File in the project          | Installed as                       | Role |
|------------------------------|------------------------------------|------|
| `bin/borgreplay-cycle`       | `/usr/local/bin/borgreplay-cycle`  | wake / replica / scrub / check / suspend cycle |
| `bin/borgreplay-check`       | `/usr/local/bin/borgreplay-check`  | health checks with mail notification |
| `sv/borgreplay-cycle/run`    | `/etc/sv/borgreplay-cycle/run`     | runit service running the cycle |
| `cron.d/borgreplay-check`    | `/etc/cron.d/borgreplay-check`     | cold boot notification (`@reboot`) |
| `etc/borgreplay-cycle.conf`  | `/etc/borgreplay-cycle.conf`       | local settings (override the defaults) |
| `client/bck_sync_to_borgreplay` | `/usr/local/bin/` on host `borg` | rsync replica and `.last_sync` marker |

## How it works

On every wake-up (or boot) `borgreplay-cycle`:

1. waits for borg to complete the replica, i.e. for `/backup/borgrepo/.last_sync`
   to become newer than the wake-up (at most `SYNC_WAIT_MIN` = 180 minutes);
2. if the last pool scrub is older than `SCRUB_EVERY_DAYS` (30) days, starts one
   and waits for it to finish;
3. runs `borgreplay-check` (with `--report` on day `REPORT_DOW`, Monday);
4. waits for the postfix queue to empty;
5. waits for the machine to be idle: no logged-in users, no rsync, no
   scrub/resilver, no `/etc/borgreplay-stay-awake` file;
6. suspends with `rtcwake -m mem -s <seconds>` until the next `WAKE_TIME`.

The `.last_sync` file is updated by the client side (host `borg`) when the
replica ends, see below.

## Client side: host `borg`

| File in the project              | Installed on `borg` (Debian 13, 192.0.2.20) |
|----------------------------------|-------------------------------------------------|
| `client/bck_sync_to_borgreplay`  | `/usr/local/bin/bck_sync_to_borgreplay`         |
| `client/crontab-root`            | root's crontab (`sudo crontab -e`)              |

The script, run as root:

1. records the start time in UTC (`YYYYMMDD_HHMMSS`);
2. copies `/mnt/backup/` to `backup@192.0.2.10:/backup/borgrepo` with
   `rsync -aAXH --delete`, using the key `/root/.ssh/id_ed25519_borgreplay`
   (alternatively, over WireGuard: `192.0.2.30`);
3. writes the start time to `/backup/borgrepo/.last_sync`. On `borgreplay` this
   is what tells `borgreplay-cycle` that the replica is done.

Root's crontab on `borg` runs it every day at 04:50:

```
50  4 * * * /usr/local/bin/bck_sync_to_borgreplay
```

It must start after `WAKE_TIME` (04:40) plus `SETTLE` (30 s): if it starts
earlier, `borgreplay` is still suspended and the replica fails. If you change
one of the two times, change the other as well.

On `borgreplay` the matching key is in `~backup/.ssh/authorized_keys`
(comment `root@borg`).

The marker is written only if `rsync` exits without errors. If the copy fails,
the script logs the error code to `borg`'s syslog (tag `bck_sync_to_borgreplay`)
and exits with the same code. On `borgreplay` the cycle waits up to
`SYNC_WAIT_MIN` minutes before suspending, and `borgreplay-check` sends the alarm
once the marker is older than `SYNC_MAX_DAYS` (2 days).

### Mail sent by `borgreplay-check`

| When                    | Subject                              |
|-------------------------|--------------------------------------|
| new problem             | `[borgreplay] ALARM: problems detected` (repeated after 23 hours if unchanged) |
| problem resolved        | `[borgreplay] Resolved: all OK`      |
| Monday                  | `[borgreplay] Report: all OK` / `PROBLEMS` |
| cold boot               | `[borgreplay] System booted`         |

On nights without problems no mail is sent.

Checks: ZFS pool health and usage, age of the last scrub, SMART, disk
temperatures (`drivetemp`), age of the last replica, root filesystem space,
WireGuard handshake, fans (`nct6775`), runit services, UPS (`apcupsd`).

## Configuration

The variables at the top of `borgreplay-cycle` can be overridden in
`/etc/borgreplay-cycle.conf`. Current configuration:

```sh
WAKE_TIME="04:40"
```

The `borgreplay-check` thresholds (recipient, percentages, temperatures...) are
changed directly in the script.

## Installation

```sh
sudo ./install.sh
```

`install.sh` only installs the `borgreplay` side. The client script is copied by
hand:

```sh
scp client/bck_sync_to_borgreplay admin@192.0.2.20:/tmp/
ssh -t admin@192.0.2.20 'sudo install -m 755 /tmp/bck_sync_to_borgreplay /usr/local/bin/'
```

Dependencies: `util-linux` (rtcwake), `zfs`, `smartmontools`, `postfix`, `cronie`.
Optional: `wireguard-tools`, `apcupsd`, `drivetemp` and `nct6775` modules.

## Usage

```sh
sudo touch /etc/borgreplay-stay-awake       # keep it awake
sudo rm /etc/borgreplay-stay-awake          # let it sleep again
sudo sv status borgreplay-cycle             # service status
sudo sv down borgreplay-cycle               # stop the cycle (until reboot)
sudo borgreplay-check --stdout              # checks on screen, no mail
grep borgreplay /var/log/socklog/user/current   # cycle log
```

## Uninstallation

```sh
sudo ./uninstall.sh
```

## Notes

- `/etc/cron.d/zfs-maintenance` (scrub on the 1st of the month at 03:00 and ntfy
  alert at 06:30) is not part of the project. With the machine suspended at
  those times it never runs: the scrub is already handled by `borgreplay-cycle`.
- If power is lost while the machine is suspended, it boots from scratch when
  power returns and the `@reboot` cron job sends the "System booted" mail.
