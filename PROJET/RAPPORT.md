# PROJET – Mise en production du portail de suivi des tournées

Bilal Chaybouti – BTC2, IPSSI Lille – Administration d'un Linux Server – 5 novembre 2026
Environnement : `srv-core` (Rocky Linux 9.8, état fin TP3, instantanés `03-fin-TP3` et `04-debut-projet`), `srv-edge` pour les tests réseau.

Les sorties ci-dessous sont copiées de mon terminal. Les captures d'écran correspondantes sont dans `preuves/captures/`, et les sorties longues dans `preuves/`.

## Contrôle des prérequis et écart constaté

| Contrôle | Résultat |
|---|---|
| `systemctl is-active helios-collect.service` + `wc -l telemetry.csv` | `active`, puis 1 → 3 lignes en 10 s (le fichier grossit) |
| `systemctl cat helios.target` | `Description=Pile applicative Helios` |
| `firewall-cmd --get-default-zone` / `--get-active-zones` | `drop` ; `internal : bond0 bond0.42` |
| `sshd -T \| grep -E '^(port\|allowgroups\|passwordauthentication) '` | `port 2242`, `passwordauthentication no`, `allowgroups ssh-admins` |
| `systemctl is-active helios-watch-auth.timer` | `active` |

**Écart corrigé avant de commencer** : l'uid **5104** imposé pour `lea` était déjà attribué au compte `sysops`, que j'avais créé au TP3 (il n'existait pas au départ). `sysops` a été renuméroté depuis la console VirtualBox, compte déconnecté (`usermod -u 5110 sysops`, `groupmod -g 5110 sysops`, puis `find / -xdev -gid 5104 -exec chgrp 5110 {} +`). Ensuite, `getent passwd 5104` ne renvoie plus rien (captures `01-uid-sysops-*`).

Ordre suivi : E8.1 (agent Zabbix) en premier, puis E1 → E7, E8, E9.

---

## 1. Tableau de conformité

| Exigence | Commande de preuve | Sortie (partie utile) |
|---|---|---|
| **E1.1** groupe et compte | `id lea` | `uid=5104(lea) gid=5003(suivi) groupes=5003(suivi)` |
| **E1.2** expiration | `chage -l lea` | `Password expires : févr. 03, 2027` · `Password inactive : févr. 10, 2027` · `Minimum … 1` · `Maximum … 90` · `warning … 14` |
| **E1.3** ni wheel ni ssh-admins | `id lea` | seul groupe : `5003(suivi)` |
| **E1.4** compte de service | `getent passwd helios-suivi` ; `ls -d /home/helios-suivi` | `helios-suivi:x:994:993:Service portail de suivi:/srv/helios/suivi:/sbin/nologin` ; `pas de dossier dans /home : OK` |
| **E2.1** www root:suivi 2770 | `ls -ld /srv/helios/suivi/www` | `drwxrws---+ 2 root suivi … /srv/helios/suivi/www` |
| **E2.2** helios-suivi rw | `getfacl www` | `user:helios-suivi:rwx` (voir `configs/getfacl-www.txt`) |
| **E2.3** zabbix stat sans liste | `runuser -u zabbix -- ls www` ; `runuser -u zabbix -- stat …/index.html` | `ls: impossible d'ouvrir le répertoire … Permission non accordée` `rc=2` ; `/srv/helios/suivi/www/index.html 46 octets` `rc=0` |
| **E2.4** héritage quel que soit l'umask | `su - lea -c 'umask 077 ; touch www/test-umask.txt'` ; `getfacl` | `-rw-rw----+ 1 lea suivi … test-umask.txt` ; `user:helios-suivi:rwx #effective:rw-` · `group:suivi:rwx #effective:rw-` · `other::---` |
| **E2.4** helios-suivi lit, nadia non | `runuser -u helios-suivi -- cat index.html` ; `runuser -u nadia -- cat index.html` | contenu affiché, `rc=0` ; `Permission non accordée`, `rc=1` |
| **E2.5** index.html par lea | `ls -l www` | `-rw-rw----+ 1 lea suivi 46 … index.html` |
| **E3** codes 0, 2, 3 | voir capture `E3-codes-retour` | `rc attendu 0 : 0` · `rc attendu 2 : 2` · `rc attendu 3 : 3` |
| **E3** JSON valide | `python3 -m json.tool www/etat.json` | `"genere": "2026-11-05T11:14:58+01:00", "hote": "srv-core", "derniere_mesure": …, "charge_1min": 0.05, "mem_dispo_ko": 1333208, "mesures": 268` |
| **E3.4** lancé par son unit (durcie) | `journalctl -u helios-suivi-publish.service -n 4` | `etat.json publie (648 mesures, charge 0.01)` · `fin d execution rc=0` · `Finished Publication de etat.json pour le portail de suivi Helios.` |
| **E3** journald | `journalctl -t helios-suivi-publish` | `etat.json publie (268 mesures, charge 0.05)` · `une autre instance tourne deja` · `repertoire publie non inscriptible : /srv/helios/suivi/www` · `fin d execution rc=0/2/3` |
| **E4.1** portail sous helios.target | `systemctl list-dependencies helios.target` | `├─helios-collect.service` `├─helios-suivi.service` |
| **E4.1** identité, ressources | `systemctl show -p User -p MemoryMax -p CPUQuotaPerSecUSec helios-suivi` | `User=helios-suivi` · `MemoryMax=134217728` · `CPUQuotaPerSecUSec=500ms` |
| **E4.1** kill -9 | `kill -9 <MainPID>` ; `sleep 5` | PID `3164` → `active`, nouveau PID `3222` |
| **E4.3** durcissement | `systemd-analyze security helios-suivi.service` | `Overall exposure level for helios-suivi.service: 1.1 OK` (`preuves/security-helios-suivi.txt`) |
| **E4.3** 200 sur / et /etat.json | `curl -w '%{http_code}'` | `/ : 200` · `/etat.json : 200` |
| **E4.4** publication planifiée | `systemctl list-timers` | `helios-suivi-publish.timer … 1min 34s left` (`preuves/timers.txt`) |
| **E4.5** aucune unit des TP modifiée | – | seuls des fichiers `helios-suivi*` ont été ajoutés dans `/etc/systemd/system` |
| **E5** délégation | `visudo -cf` puis `install -m 0440 -o root -g root` ; `visudo -c` ; `sudo -l -U lea` | `/etc/sudoers.d/92-helios-suivi : analyse réussie` ; 5 commandes exactes (`preuves/sudo-l-lea.txt`) |
| **E5** autorisé / refusé | `sudo -l -U lea /usr/bin/systemctl restart helios-suivi.service` ; `… restart sshd` ; `… journalctl … --vacuum-time=1s` | `rc=0` ; rien, `rc=1` ; rien, `rc=1` |
| **E5** essai réel | `su - lea` puis `sudo systemctl restart helios-suivi.service` ; `sudo systemctl restart sshd` | `rc=0` ; `Désolé, l'utilisateur lea n'est pas autorisé à exécuter « /bin/systemctl restart sshd »` |
| **E6.1** 8080 dans internal seulement | `firewall-cmd --zone=internal --query-port=8080/tcp` (runtime puis `--permanent`) ; `--list-all-zones \| grep -n 8080` ; `nft list ruleset \| grep 8080` | `yes` / `yes` ; une seule ligne : `82: ports: 10051/tcp 2242/tcp 8080/tcp` (zone internal) ; `tcp dport 8080 accept` |
| **E6.2** zone par défaut | `firewall-cmd --get-default-zone` | `drop` |
| **E6.3** depuis srv-edge | `curl http://10.42.0.10:8080/etat.json` ; `nc -zv -w2 192.168.56.10 8080` | `reseau metier : 200` ; `Ncat: No route to host.` `rc=1` |
| **E7.1** sshd inchangé | `sshd -T \| grep -E '^(port\|permitrootlogin\|passwordauthentication\|allowgroups) '` | `port 2242` · `permitrootlogin no` · `passwordauthentication no` · `allowgroups ssh-admins` |
| **E7.2** lea sans SSH | `ssh -p 2242 lea@192.168.56.10` (srv-edge) ; `journalctl -u sshd -g lea` | `Permission denied (publickey)` ; `User lea from 192.168.56.11 not allowed because none of user's groups are listed in AllowGroups` |
| **E7.3** détection et journald | `systemctl is-active helios-watch-auth.timer` ; `grep Storage …` ; `journalctl --list-boots` | `active` ; `Storage=persistent` ; 3 démarrages listés |
| **E8.1** agent, zabbix-get, sysstat | `systemctl is-active zabbix-agent2 sysstat-collect.timer` ; `grep ^Server=` | `active` `active` ; `Server=127.0.0.1` (zabbix-agent2 7.0.32) |
| **E8.3/4** sondes | `zabbix_get -s 127.0.0.1 -k helios.suivi.http` ; `-k helios.suivi.age` | `200` ; `3` |
| **E9.0** répertoire | `ls -ld /srv/helios/archives /srv/helios/archives/suivi` | `drwxr-x---. 3 helios helios … /srv/helios/archives` · `drwxr-x---. 2 root root … /srv/helios/archives/suivi` |
| **E9.1/3** archives, empreintes, rétention | 3 sauvegardes après 5 existantes ; `ls … \| wc -l` ; `sha256sum -c` | `rc=0` ×3 ; `7` archives, `7` empreintes ; `retention : 1 archive(s) supprimee(s), 7 conservees au maximum` ; `suivi-20261105-113316.tar.gz: Réussi` |
| **E9.2** contenu | `tar -tzvf <archive>` | `srv/helios/suivi/www/index.html`, `etat.json`, les 5 units, `etc/sudoers.d/92-helios-suivi`, `etc/zabbix/zabbix_agent2.d/helios-suivi.conf`, les 2 scripts |
| **E9.4** timer | `systemctl list-timers helios-suivi-backup.timer` | `Fri 2026-11-06 03:15:00 CET` ; `Persistent=true` |
| **E9.5** restauration | voir §3 | `ACL identiques` ; `ACL de index.html restaurees` |
| **SELinux** (contrainte §4) | `ausearch -m AVC -ts today` | `<no matches>` : aucun refus SELinux, rien à diagnostiquer, SELinux resté en enforcing |
| **Persistance** | `systemctl reboot` puis revérification | 9 × `active`, `portail : 200`, `zabbix_get` → `200` / `113`, `query-port` → `yes`, sshd inchangé (capture `reboot-verification`) |

E10 (audit) et RUNBOOK.md (bonus) : non réalisés.

---

## 2. Justifications

**(a) Durcissement de `helios-suivi.service`** – Le modèle est `helios-collect.service` (TP1). Le portail n'écrit nulle part : `ProtectSystem=strict` **sans aucun** `ReadWritePaths`, `ProtectHome`, `PrivateTmp`, `PrivateDevices`. Isolation : `PrivateUsers`, `ProtectProc=invisible`, `ProcSubset=pid`, `ProtectKernel*`, `ProtectClock`, `ProtectHostname`, `RestrictNamespaces`, `RestrictRealtime`, `RestrictSUIDSGID`, `LockPersonality`, `MemoryDenyWriteExecute`, `CapabilityBoundingSet=` vide (8080 > 1024, aucun privilège nécessaire), `SystemCallFilter=@system-service` moins `@privileged @resources`, `RestrictAddressFamilies=AF_INET AF_UNIX`. Score : **1.1 OK**. Aucune directive n'a dû être retirée : Python `http.server` ne fait que lire, sans JIT ni privilège. Ce qui reste exposé est inhérent au service : l'accès réseau (`PrivateNetwork` impossible pour un serveur HTTP, 0.5) et les sockets INET (0.3).

**(b) `--x` et non `r-x` pour zabbix sur `www`** – Sur un répertoire, `x` permet de **traverser** le répertoire pour atteindre un fichier dont on connaît le nom, et `r` permet d'en **lister** le contenu. La sonde `helios.suivi.age` n'a besoin que de `stat` sur `etat.json` (lire une date ne demande aucun droit sur le fichier lui-même, seulement la traversée des répertoires). `r-x` permettrait de découvrir tous les fichiers publiés, ce qui est inutile : c'est le moindre privilège. **Observé sans l'entrée** (`setfacl -x u:zabbix www`) : `stat: impossible d'exécuter statx '/srv/helios/suivi/www/etat.json': Permission non accordée`, et la sonde échoue (`sh: ligne 1: 1793874667 - : erreur de syntaxe`). Après `setfacl -m u:zabbix:--x`, la sonde renvoie `67`. Le parent `/srv/helios/suivi` porte aussi `user:zabbix:--x`.

**(c) Le joker `*` dans une règle sudo journalctl** – `journalctl -u helios-suivi.service *` laisserait l'utilisateur ajouter **n'importe quelle option, en root** : `--vacuum-time=1s` ou `--vacuum-size=1` **efface tous les journaux** du serveur (destruction des traces), `--rotate` force une rotation, `-f` bloque une session root. Sans `--no-pager`, journalctl et `systemctl status` ouvrent `less` en root, et `!sh` donne un shell root : c'est le même mécanisme que l'évasion `sudo vim` du TP2. Ma règle liste chaque commande **complète, avec ses arguments exacts et `--no-pager` imposé** : sudo refuse toute option supplémentaire. Vérifié : `sudo -l -U lea /usr/bin/journalctl --no-pager -n 100 -u helios-suivi.service --vacuum-time=1s` ne liste rien (`rc=1`). Pas de `NOPASSWD`, fichier validé par `visudo -cf` avant `install -m 0440 -o root -g root`.

---

## 3. Test de restauration (E9.5)

**(a) Extraction dans un répertoire de test et comparaison des ACL**
```
# DER=$(ls -1t /srv/helios/archives/suivi/suivi-*.tar.gz | head -1) ; echo "$DER"
/srv/helios/archives/suivi/suivi-20261105-113433.tar.gz
# mkdir /root/restore-test ; tar --acls --xattrs -xzpf "$DER" -C /root/restore-test
# cd /srv && getfacl -R helios/suivi/www | grep -v etat.json > /root/acl-prod.txt
# cd /root/restore-test/srv && getfacl -R helios/suivi/www | grep -v etat.json > /root/acl-restore.txt
# diff /root/acl-prod.txt /root/acl-restore.txt && echo "ACL identiques"
ACL identiques
```
(`etat.json` est exclu de la comparaison : il est régénéré toutes les 2 minutes.)

**(b) Incident simulé : suppression puis restauration de `index.html` seul**
```
# getfacl /srv/helios/suivi/www/index.html > /root/acl-index-avant.txt
# rm -f /srv/helios/suivi/www/index.html
# curl -s -o /dev/null -w "apres suppression : %{http_code}\n" http://127.0.0.1:8080/
apres suppression : 200
# time tar --acls --xattrs -xzpf "$DER" -C / srv/helios/suivi/www/index.html
real    0m0,065s
user    0m0,015s
sys     0m0,021s
# ls -l /srv/helios/suivi/www/index.html
-rw-rw----+ 1 lea suivi 46  5 nov.  11:10 /srv/helios/suivi/www/index.html
# getfacl /srv/helios/suivi/www/index.html | diff /root/acl-index-avant.txt - && echo "ACL de index.html restaurees"
ACL de index.html restaurees
# curl -s -w "\napres restauration : %{http_code}\n" http://127.0.0.1:8080/
<h1>Portail de suivi des tournees Helios</h1>
apres restauration : 200
```
**Temps** : 0,065 s pour l'extraction. L'opération complète (repérer l'archive, restaurer, vérifier) a pris moins d'une minute. Le propriétaire (`lea`), le groupe (`suivi`), le mode et les ACL sont restaurés, et le reste de `www` n'a pas été touché.

Observation : sans `index.html`, le portail répond quand même **200**, car `http.server` affiche alors la **liste du répertoire**. Un contrôle sur le seul code HTTP ne détecte donc pas cette panne (voir §5).

---

## 4. Mesure sous charge

Pendant `for i in $(seq 2000); do curl -s -o /dev/null http://127.0.0.1:8080/etat.json; done` (`real 0m57,743s`), avec `sar -u 1 30` en parallèle (`preuves/sar-charge.txt`) :

| | Avant | Après |
|---|---|---|
| `CPUUsageNSec` | `507217000` | `5899676000` |
| `MemoryCurrent` | `10215424` | `10235904` |
| `sar -u` (moyenne, 2 CPU) | – | `%user 13,36` · `%system 49,40` · `%idle 37,02` |

**Le quota `CPUQuota=50%` n'a pas joué** : le portail a consommé 5,39 s de CPU en 57,7 s, soit **≈ 9 % d'un CPU**, très loin du plafond de 500 ms/s. La charge observée par `sar` (49 % de temps système) vient surtout des **2 000 processus `curl`** lancés en série. La mémoire du service reste stable (+20 Ko, ≈ 10 Mo pour 128 Mo autorisés).

---

## 5. Limites connues

- **Page d'accueil manquante non détectée** : sans `index.html`, le portail affiche la liste de `www` et renvoie 200. La sonde `helios.suivi.http` vise `/etat.json` et ne le voit pas. Avec une journée de plus : une sonde sur `/` qui vérifie le contenu, et une page d'index générée par défaut.
- **Écart d'uid** : `sysops` (créé au TP3) occupait l'uid 5104 et a été renuméroté en 5110.
- **Sauvegarde exécutée en root** : nécessaire pour lire le fichier sudoers et les units. Son unit est restreinte à l'écriture dans `/srv/helios/archives/suivi` (`ProtectSystem=strict`, `PrivateNetwork`). On pourrait aller plus loin (`CapabilityBoundingSet` limité à `CAP_DAC_READ_SEARCH`).
- **Test de rétention** : 9 lancements en 1 s ont déclenché la protection systemd `start-limit-hit` (5 démarrages / 10 s). Ce n'est pas une erreur du script (aucune erreur dans `journalctl -t helios-suivi-backup`) ; le test a été refait avec 3 s d'intervalle.
- **Sauvegardes locales** : les archives restent sur `srv-core`. Une vraie sauvegarde devrait être copiée sur une autre machine.
- **Non réalisés** (bonus) : E8.5 (frontend Zabbix, déclencheurs), E10 (script d'audit), RUNBOOK.md.
