# borgreplay

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

Il file `.last_sync` viene aggiornato dal lato client (host `borg`) a fine replica.

### Mail inviate da `borgreplay-check`

| Quando                  | Oggetto                              |
|-------------------------|--------------------------------------|
| problema nuovo          | `[borgreplay] ALLARME: problemi rilevati` (ripetuta dopo 23 ore se invariato) |
| problema risolto        | `[borgreplay] Rientrato: tutto OK`   |
| lunedi'                 | `[borgreplay] Rapporto: tutto OK` / `PROBLEMI` |
| avvio a freddo          | `[borgreplay] Sistema avviato`       |

Nelle notti senza problemi non parte nessuna mail.

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
  zero e il cron `@reboot` manda la mail "Sistema avviato".
