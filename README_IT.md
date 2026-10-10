# borgreplay

[English](README.md) | **Italiano**

Ciclo giornaliero veglia / replica / controllo / sospensione per il server di
replica Borg `borgreplay` (Void Linux, runit, pool ZFS `backup`).

La macchina passa la giornata sospesa in RAM (S3). Ogni notte si sveglia da sola
tramite l'RTC, riceve la replica Borg, esegue i controlli di salute, manda le
eventuali mail e torna a dormire fino alla notte successiva.

## Componenti

| File nel progetto            | Installato in                      | Ruolo |
|------------------------------|------------------------------------|-------|
| `bin/borgreplay-cycle`       | `/usr/local/bin/borgreplay-cycle`  | ciclo veglia / replica / scrub / check / sospensione |
| `bin/borgreplay-check`       | `/usr/local/bin/borgreplay-check`  | controlli di salute con notifica via mail |
| `sv/borgreplay-cycle/run`    | `/etc/sv/borgreplay-cycle/run`     | servizio runit che esegue il ciclo |
| `cron.d/borgreplay-check`    | `/etc/cron.d/borgreplay-check`     | notifica di avvio a freddo (`@reboot`) |
| `etc/borgreplay-cycle.conf`  | `/etc/borgreplay-cycle.conf`       | impostazioni locali (sovrascrive i default) |
| `client/bck_sync_to_borgreplay` | `/usr/local/bin/` sull'host `borg` | replica rsync e scrittura del marker `.last_sync` |

## Funzionamento

A ogni risveglio (o avvio) `borgreplay-cycle`:

1. aspetta che borg completi la replica, cioe' che `/backup/borgrepo/.last_sync`
   diventi piu' recente del risveglio (massimo `SYNC_WAIT_MIN` = 180 minuti);
2. se l'ultimo scrub del pool ha piu' di `SCRUB_EVERY_DAYS` (30) giorni lo avvia
   e ne attende la fine;
3. esegue `borgreplay-check` (con `--report` il giorno `REPORT_DOW`, lunedi');
4. attende che la coda di postfix si svuoti;
5. aspetta che la macchina sia libera: nessun utente collegato, nessun rsync,
   nessuno scrub/resilver, nessun file `/etc/borgreplay-stay-awake`;
6. sospende con `rtcwake -m mem -s <secondi>` fino alla prossima `WAKE_TIME`.

Il file `.last_sync` viene aggiornato dal lato client (host `borg`) a fine replica,
vedi sotto.

## Lato client: host `borg`

| File nel progetto                | Installato su `borg` (Debian 13, 192.0.2.20) |
|----------------------------------|--------------------------------------------------|
| `client/bck_sync_to_borgreplay`  | `/usr/local/bin/bck_sync_to_borgreplay`          |
| `client/crontab-root`            | crontab di root (`sudo crontab -e`)              |

Lo script, lanciato da root:

1. annota l'ora di inizio in UTC (`YYYYMMDD_HHMMSS`);
2. copia `/mnt/backup/` in `backup@192.0.2.10:/backup/borgrepo` con
   `rsync -aAXH --delete`, usando la chiave `/root/.ssh/id_ed25519_borgreplay`
   (in alternativa, via WireGuard: `192.0.2.30`);
3. scrive l'ora di inizio in `/backup/borgrepo/.last_sync`. Su `borgreplay` e'
   questo a far capire a `borgreplay-cycle` che la replica e' finita.

Lo lancia ogni giorno alle 04:50 il crontab di root su `borg`:

```
50  4 * * * /usr/local/bin/bck_sync_to_borgreplay
```

Deve partire dopo `WAKE_TIME` (04:40) piu' `SETTLE` (30 s): se parte prima,
`borgreplay` e' ancora sospesa e la replica fallisce. Se si cambia uno dei due
orari va cambiato anche l'altro.

Sulla macchina `borgreplay` la chiave corrispondente e' in
`~backup/.ssh/authorized_keys` (commento `root@borg`).

Il marker viene scritto solo se `rsync` termina senza errori. Se la copia fallisce,
lo script scrive il codice d'errore nel syslog di `borg` (tag
`bck_sync_to_borgreplay`) ed esce con lo stesso codice. Su `borgreplay` il ciclo
attende fino a `SYNC_WAIT_MIN` minuti prima di sospendere, e `borgreplay-check`
manda l'allarme quando il marker supera `SYNC_MAX_DAYS` (2 giorni).

### Mail inviate da `borgreplay-check`

| Quando                  | Oggetto                              |
|-------------------------|--------------------------------------|
| problema nuovo          | `[borgreplay] ALARM: problems detected` (ripetuta dopo 23 ore se invariato) |
| problema risolto        | `[borgreplay] Resolved: all OK`      |
| lunedi'                 | `[borgreplay] Report: all OK` / `PROBLEMS` |
| avvio a freddo          | `[borgreplay] System booted`         |

Nelle notti senza problemi non parte nessuna mail. Mail, log e commenti degli
script sono in inglese.

Controlli: stato e occupazione del pool ZFS, eta' dell'ultimo scrub, SMART,
temperature dei dischi (`drivetemp`), eta' dell'ultima replica, spazio sulla
root, handshake WireGuard, ventole (`nct6775`), servizi runit, UPS (`apcupsd`).

## Configurazione

Le variabili all'inizio di `borgreplay-cycle` si possono sovrascrivere in
`/etc/borgreplay-cycle.conf`. Configurazione attuale:

```sh
WAKE_TIME="04:40"
```

Le soglie di `borgreplay-check` (destinatario, percentuali, temperature...) si
cambiano direttamente nello script.

## Installazione

```sh
sudo ./install.sh
```

`install.sh` installa solo la parte di `borgreplay`. Sul client va copiato a mano:

```sh
scp client/bck_sync_to_borgreplay admin@192.0.2.20:/tmp/
ssh -t admin@192.0.2.20 'sudo install -m 755 /tmp/bck_sync_to_borgreplay /usr/local/bin/'
```

Dipendenze: `util-linux` (rtcwake), `zfs`, `smartmontools`, `postfix`, `cronie`.
Opzionali: `wireguard-tools`, `apcupsd`, moduli `drivetemp` e `nct6775`.

## Uso

```sh
sudo touch /etc/borgreplay-stay-awake       # tienila sveglia
sudo rm /etc/borgreplay-stay-awake          # lasciala riaddormentare
sudo sv status borgreplay-cycle             # stato del servizio
sudo sv down borgreplay-cycle               # ferma il ciclo (fino al riavvio)
sudo borgreplay-check --stdout              # controlli a video, senza mail
grep borgreplay /var/log/socklog/user/current   # log del ciclo
```

## Disinstallazione

```sh
sudo ./uninstall.sh
```

## Note

- `/etc/cron.d/zfs-maintenance` (scrub il 1 del mese alle 03:00 e avviso ntfy
  alle 06:30) non fa parte del progetto. Con la macchina sospesa a quegli orari
  non viene eseguito: lo scrub e' gia' gestito da `borgreplay-cycle`.
- Se manca la corrente mentre la macchina e' sospesa, al ritorno riparte da
  zero e il cron `@reboot` manda la mail "System booted".
