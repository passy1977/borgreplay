borgreplay installed.

1. Set MAILTO in /etc/borgreplay.env and WAKE_TIME in /etc/borgreplay-cycle.conf.
   WAKE_TIME must come before the replica job on the Borg host.
2. Enable the service (the machine will suspend when idle):
     ln -s /etc/sv/borgreplay-cycle /var/service/
3. The client script for the Borg host is in /usr/share/doc/borgreplay/client/.
