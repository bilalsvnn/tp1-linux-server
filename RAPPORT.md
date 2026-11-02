# TP1 – systemd, réseau avancé et automatisation (Hélios)
Bilal Chaybouti – BTC2 IPSSI Lille – 02/11/2026 – Rocky Linux 9.8 (srv-core 192.168.56.10, srv-edge 192.168.56.11)

## Mission 1 – systemd
- Boot avant : **1 min 43,820 s** (NetworkManager-wait-online 1 min 0,047 s, kdump 24,2 s). Après masquage de wait-online, désactivation de firewalld (temporaire) et de kdump (initiative justifiée) : **21,577 s** (−80 %). Graphiques : captures/boot-avant.svg, boot-apres.svg.
- helios-collect.service : active, enabled ; après `kill -9`, relancé automatiquement (PID 945 → 1045) grâce à `Restart=on-failure` + `RestartSec=5s`.
- Drop-in override.conf : CPUQuota=20 % (200ms), **MemoryMax=100663296**, IOWeight=50, Nice=5, intervalle 5 s. L'unit d'origine n'est pas modifiée.
- `CapabilityBoundingSet=` vide (volontaire) : aucune capability.
- Score `systemd-analyze security` : **5.3 MEDIUM → 0.6 SAFE** après durcissement (Private*, Protect*, Restrict*, SystemCallFilter=@system-service, MemoryDenyWriteExecute, UMask=0027).
- helios.target liste helios-collect.service.
- Priorités : nice 19 → 5 (renice), ionice best-effort prio 7, chrt SCHED_OTHER.

## Mission 2 – Réseau
- bond0 active-backup (miimon=100, primary=enp0s9, fail_over_mac=active), 10.42.0.10/24, MII up sur les deux ports.
- Bascule (`setlinkstate3 off`) : 180 ICMP envoyés, 178 reçus → **2 perdus** ; enp0s10 devient actif.
- VLAN 42 bond0.42 (10.42.42.10) ↔ enp0s9.42 sur srv-edge (10.42.42.11) ; tcpdump : `ethertype 802.1Q (0x8100) … vlan 42`.
- Table 142 transport, règle `100: from 10.42.42.10 lookup transport` ; `ip route get 8.8.8.8 from 10.42.42.10` → via 10.42.42.11 dev bond0.42 ; sans source → via 10.0.2.2 dev enp0s3.
- Tout est persistant après `systemctl reboot`.

## Mission 3 – Automatisation
- helios-archive.sh : rc=0 (archive + purge), **rc=2** (verrou flock pris), **rc=3** (source absente) ; traces dans `journalctl -t helios-archive`.
- helios-archive.timer : NEXT mar. 03/11/2026 02:30 CET ; service oneshot status=0/SUCCESS.

| Critère | cron | Timer systemd |
|---|---|---|
| Exécution manquée (VM éteinte) | Perdue | Rattrapée (`Persistent=yes`) |
| Logs | syslog/mail, non lié à la tâche | journald + `systemctl status` (code retour) |
| Dépendances | Aucune | `After=`, `Requires=`, `Condition*=` |
| Ressources | nice manuel | `Nice=`, `IOSchedulingClass=`, `CPUQuota=` |
| Étalement de charge | Non | `RandomizedDelaySec=` |
| Prochaine exécution | Invisible | `systemctl list-timers` |

Observé : le journal de crond ne mentionne ni la tâche ni son échéance.

## Bonus
helios-inbox.path (`PathChanged=/srv/helios/inbox`) : `touch test.csv` déclenche l'archivage (rc=0). `PathChanged` plutôt que `PathExistsGlob` pour éviter une boucle (le fichier reste dans l'inbox → unit-start-limit-hit).
