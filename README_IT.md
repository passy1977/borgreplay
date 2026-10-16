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
| `etc/cycle.conf`  | `/etc/borgreplay/cycle.conf`       | impostazioni locali (sovrascrive i default) |
| `client/bck_sync_to_borgreplay` | `/usr/local/bin/` sull'host Borg | replica rsync e scrittura del marker `.last_sync` |
| `.env` (da `.env.sample`)    | `/etc/borgreplay/borgreplay.env` su entrambi gli host | impostazioni locali: indirizzi, utenti, destinatario mail |

## Funzionamento

A ogni risveglio (o avvio) `borgreplay-cycle`:

1. aspetta che borg completi la replica, cioe' che `/backup/borgrepo/.last_sync`
   diventi piu' recente del risveglio (massimo `SYNC_WAIT_MIN` = 360 minuti);
   se il marker contiene una richiesta `stay-awake`, crea
   `/etc/borgreplay/stay-awake` (vedi [Stay-awake remoto](#stay-awake-remoto));
2. se l'ultimo scrub del pool ha piu' di `SCRUB_EVERY_DAYS` (30) giorni lo avvia
   e ne attende la fine;
3. esegue `borgreplay-check` (con `--report` il giorno `REPORT_DOW`, lunedi');
4. attende che la coda di postfix si svuoti;
5. aspetta che la macchina sia libera: nessun utente collegato, nessun rsync,
   nessuno scrub/resilver, nessun file `/etc/borgreplay/stay-awake`;
6. sospende con `rtcwake -m mem -s <secondi>` fino alla prossima `WAKE_TIME`.

Il file `.last_sync` viene aggiornato dal lato client (l'host Borg) a fine replica,
vedi sotto.

## Lato client: l'host Borg

| File nel progetto                | Installato sull'host Borg                        |
|----------------------------------|--------------------------------------------------|
| `client/bck_sync_to_borgreplay`  | `/usr/local/bin/bck_sync_to_borgreplay`          |
| `.env`                           | `/etc/borgreplay/borgreplay.env`                            |
| `client/crontab-root`            | crontab di root (`sudo crontab -e`)              |

Lo script, lanciato da root:

1. aspetta che nessun repository sia bloccato da un backup Borg in corso
   (`lock.exclusive` o `lock.roster`), al massimo `LOCK_WAIT_MIN` (120) minuti:
   altrimenti i backup che si sovrappongono all'orario della replica
   cambierebbero i file durante la copia;
2. annota l'ora di inizio in UTC (`YYYYMMDD_HHMMSS`) e copia `/mnt/backup/` in
   `$REPLICA_USER@$REPLICA_HOST:/backup/borgrepo` con `rsync -aAXH --delete`,
   usando la chiave `$SSH_KEY` (predefinita `/root/.ssh/id_ed25519_borgreplay`);
   se un backup parte durante la copia (codice 24 di rsync, file spariti)
   aspetta di nuovo e ripete la copia, al massimo `COPY_TRIES` (3) volte. Il
   marker e' escluso da `--delete`, quindi una copia fallita lascia quello
   precedente;
3. scrive l'ora di inizio in `/backup/borgrepo/.last_sync`. Su `borgreplay` e'
   questo a far capire a `borgreplay-cycle` che la replica e' finita.

Lo lancia ogni giorno alle 04:50 il crontab di root sull'host Borg:

```
50  4 * * * /usr/local/bin/bck_sync_to_borgreplay
```

Deve partire dopo `WAKE_TIME` (04:40) piu' `SETTLE` (30 s): se parte prima,
`borgreplay` e' ancora sospesa e la replica fallisce. Se si cambia uno dei due
orari va cambiato anche l'altro.

Su `borgreplay` la chiave pubblica corrispondente e' negli `authorized_keys` di
`$REPLICA_USER`.

Il marker viene scritto solo se `rsync` termina senza errori. Se la copia fallisce,
lo script scrive il codice d'errore nel syslog dell'host Borg (tag
`bck_sync_to_borgreplay`) ed esce con lo stesso codice. Su `borgreplay` il ciclo
attende fino a `SYNC_WAIT_MIN` minuti prima di sospendere, e `borgreplay-check`
manda l'allarme quando il marker supera `SYNC_MAX_DAYS` (2 giorni).

Se la replica fallisce parte subito anche una mail dall'host Borg (oggetto
`[borg] Replica FAILED (rsync code N)`, con gli ultimi messaggi di rsync): se
`borgreplay` non si e' svegliata non puo' segnalarlo da sola. La mail va a
`MAILTO` attraverso `SMTP_RELAY` usando `python3`, quindi sull'host Borg non
serve un server di posta; il relay deve accettare posta da quell'host.

## Stay-awake remoto

`borgreplay` e' raggiungibile solo nei pochi minuti della replica notturna. Per
tenerla accesa per un intervento senza dover essere li' alle 04:40, la richiesta
si fa dall'host Borg: viaggia insieme alla replica, dentro il marker.

```
Host Borg                                borgreplay
---------                                ----------
touch /etc/borgreplay/stay-awake.request
04:50  rsync /mnt/backup/  ------------> /backup/borgrepo/
       marker "<data> stay-awake" -----> /backup/borgrepo/.last_sync
       file di richiesta cancellato      borgreplay-cycle vede "stay-awake"
                                         crea /etc/borgreplay/stay-awake
                                         resta accesa finche' non lo cancelli
```

1. **Richiesta**, sull'host Borg:

   ```sh
   sudo touch /etc/borgreplay/stay-awake.request
   ```

   La replica successiva, di solito quella notturna del cron, scrive il marker
   come `YYYYMMDD_HHMMSS stay-awake` e cancella il file di richiesta. La
   richiesta vale una volta sola: per un'altra notte va ricreata. Se la
   scrittura del marker fallisce la richiesta resta e viene ritentata alla
   replica successiva.

2. **Intervento** su `borgreplay`: dopo la replica non va in sospensione.
   `/etc/borgreplay/stay-awake` contiene una nota con l'ora e la replica che
   l'ha chiesto, e nel log compare
   `stay-awake requested by the replica, /etc/borgreplay/stay-awake created`.

3. **Rilascio** a fine lavoro, su `borgreplay`:

   ```sh
   sudo rm /etc/borgreplay/stay-awake
   ```

   Entro un minuto, quando non ci sono piu' utenti collegati, la macchina va in
   sospensione fino alla prossima `WAKE_TIME`.

Se `borgreplay` e' gia' sveglia la richiesta si puo' mandare subito, senza
aspettare la notte:

```sh
sudo bck_sync_to_borgreplay --stay-awake    # sull'host Borg
```

Il percorso del file di richiesta e' `STAY_AWAKE_REQUEST` in `.env`
(predefinito `/etc/borgreplay/stay-awake.request`). Le due parti sono
compatibili tra versioni: un client vecchio non fa richieste, un
`borgreplay-cycle` vecchio le ignora.

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

Le impostazioni locali stanno in `.env`, che git non traccia. Si parte dal
modello:

```sh
cp .env.sample .env
```

| Variabile      | Usata da                   | Significato |
|----------------|----------------------------|-------------|
| `MAILTO`       | `borgreplay-check`         | destinatario delle mail |
| `REPLICA_HOST` | `bck_sync_to_borgreplay`   | indirizzo di `borgreplay` visto dall'host Borg: un nome DNS o un IP riservato, perché un indirizzo DHCP può cambiare dopo una sospensione; root sull'host Borg deve conoscerne la chiave host con questo nome |
| `REPLICA_USER` | `bck_sync_to_borgreplay`   | utente proprietario di `/backup/borgrepo` su `borgreplay` |
| `SSH_KEY`      | `bck_sync_to_borgreplay`   | chiave SSH di root sull'host Borg (facoltativa) |
| `STAY_AWAKE_REQUEST` | `bck_sync_to_borgreplay` | file di richiesta per lo [stay-awake remoto](#stay-awake-remoto) (facoltativa) |
| `SMTP_RELAY`   | `bck_sync_to_borgreplay`   | relay SMTP (`host` o `host:porta`) per la mail di replica fallita; vuota = nessuna mail |
| `MAILFROM`     | `bck_sync_to_borgreplay`   | mittente di quella mail (facoltativa, predefinito `root@<fqdn>`) |
| `CLIENT_HOST`, `CLIENT_USER` | `install-client.sh` | dove installare il lato client |

Le variabili all'inizio di `borgreplay-cycle` si possono sovrascrivere in
`/etc/borgreplay/cycle.conf`. Configurazione attuale:

```sh
WAKE_TIME="04:40"
```

Le soglie di `borgreplay-check` (destinatario, percentuali, temperature...) si
cambiano direttamente nello script.

## Installazione

```sh
sudo ./install.sh
```

`install.sh` installa la parte di `borgreplay`, compreso `.env` come
`/etc/borgreplay/borgreplay.env`. Il lato client si installa via SSH da questa macchina
(chiede la password di sudo sull'host Borg):

```sh
./install-client.sh
```

La riga di crontab in `client/crontab-root` va aggiunta a mano sull'host Borg.

Dipendenze: `util-linux` (rtcwake), `zfs`, `smartmontools`, `postfix`, `cronie`.
Opzionali: `wireguard-tools`, `apcupsd`, moduli `drivetemp` e `nct6775`.

### Pacchetto Void Linux

Al posto di `install.sh` si puo' creare e installare un pacchetto `xbps`:

```sh
packaging/void/build.sh
sudo xbps-install --repository "$PWD/dist" borgreplay
sudo ln -s /etc/sv/borgreplay-cycle /var/service/    # abilita il servizio
```

Il pacchetto installa gli script in `/usr/bin`, il servizio runit, il file cron
e la documentazione (con lo script del client) in `/usr/share/doc/borgreplay`.
`/etc/borgreplay/borgreplay.env` e `/etc/borgreplay/cycle.conf` sono file di configurazione:
il pacchetto li installa commentati e gli aggiornamenti mantengono le tue
modifiche. Dopo la prima installazione vanno impostati `MAILTO` e `WAKE_TIME`.

Tutte le impostazioni e il file di stay-awake stanno in `/etc/borgreplay/`
(prima della 1.2 erano `/etc/borgreplay.env`, `/etc/borgreplay-cycle.conf` e
`/etc/borgreplay-stay-awake`). L'aggiornamento del pacchetto, `install.sh` e
`install-client.sh` spostano da soli i file vecchi nella nuova cartella.

Per passare da `install.sh` al pacchetto: salva i file in `/etc/borgreplay/`, lancia
`sudo ./uninstall.sh` e installa il pacchetto, altrimenti le copie in
`/usr/local/bin` hanno la precedenza. Per una nuova versione si aumenta
`VERSION` o `REVISION` in `packaging/void/build.sh`.

## Uso

```sh
sudo touch /etc/borgreplay/stay-awake       # tienila sveglia
sudo rm /etc/borgreplay/stay-awake          # lasciala riaddormentare
cat /backup/borgrepo/.last_sync             # ultima replica (ed eventuale stay-awake)
sudo sv status borgreplay-cycle             # stato del servizio
sudo sv down borgreplay-cycle               # ferma il ciclo (fino al riavvio)
sudo borgreplay-check --stdout              # controlli a video, senza mail
grep borgreplay /var/log/socklog/user/current   # log del ciclo
```

Sull'host Borg:

```sh
sudo touch /etc/borgreplay/stay-awake.request   # tieni sveglia borgreplay dopo la prossima replica
sudo bck_sync_to_borgreplay --stay-awake        # lo stesso, subito (borgreplay deve essere sveglia)
journalctl -t bck_sync_to_borgreplay            # log del client
```

## Disinstallazione

```sh
sudo ./uninstall.sh
```

## Note

- `/etc/cron.d/zfs-maintenance` (scrub il 1 del mese alle 03:00 e avviso
  alle 06:30) non fa parte del progetto. Con la macchina sospesa a quegli orari
  non viene eseguito: lo scrub e' gia' gestito da `borgreplay-cycle`.
- Se manca la corrente mentre la macchina e' sospesa, al ritorno riparte da
  zero e il cron `@reboot` manda la mail "System booted".

## Licenza

GPL-2.0-only, vedi [LICENSE](LICENSE).
