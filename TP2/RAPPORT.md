# TP2 – Gestion avancée des utilisateurs, permissions, ACL et sudoers (Hélios)
Bilal Chaybouti – BTC2 IPSSI Lille – 03/11/2026 – Rocky Linux 9.8, srv-core

## Mission 1 – Comptes et authentification
- login.defs : PASS_MAX_DAYS 90, PASS_MIN_DAYS 1, PASS_WARN_AGE 14, UMASK 027 (posés avant la création des comptes).
- pwquality : minlen 12, minclass 3, maxrepeat 3, dictcheck, usercheck, enforce_for_root → « moins de 12 caractères » refusé.
- faillock : deny 5, fail_interval 900, unlock_time 600, audit. Aucun profil authselect n'était sélectionné : `authselect select sssd with-faillock --force --backup=avant-tp2`.
- 6 échecs → 5 enregistrés, compte verrouillé au 5e ; vide après `faillock --reset`.
- Comptes : julien 5100 (transport + helios-ops, admin du groupe transport), nadia 5101, tarek 5102 (telemetry + transport), audit-ext 5103 (expire le 24/11/2026).

## Mission 2 – Bits spéciaux et umask
- transport 2770 (setgid) : fichier de tarek → groupe transport ; témoin 0770 → groupe telemetry.
- depot 1777 (sticky) : tarek ne peut pas supprimer le fichier de nadia (rc=1) ; en 0777 il le peut (rc=0).

| Cas | umask | Prédit | Observé |
|---|---|---|---|
| u1 / d1 | 027 | 640 / 750 | -rw-r----- / drwxr-x--- |
| u2 / d2 | 002 | 664 / 775 | -rw-rw-r-- / drwxrwxr-x |
| u3 | 077 | 600 | -rw------- |

- /etc/profile.d/helios-umask.sh : 002 pour les membres de transport, 027 sinon (nadia 0002, audit-ext 0027).
- setuid ignoré sur un script (id → nadia). helios-lastlog setgid telemetry (2755) : tail direct refusé, helios-lastlog autorisé.

## Mission 3 – ACL
- `setfacl -R -m u:audit-ext:rX` : lecture sans écriture, `+` dans ls -l.
- ACL par défaut (audit-ext r, transport rwx, other ---) : les nouveaux fichiers et sous-dossiers en héritent ; l'auditeur lit tournee-j2.csv (rc=0).
- **chmod g-w sur un fichier avec ACL modifie le masque** (rwx → r-x), pas `group::`. Les entrées nominatives sont plafonnées (#effective:r-x) : tarek perd l'écriture malgré `user:tarek:rwx` ; `setfacl -m m::rwx` la rétablit.
- Sauvegarde `getfacl -R` (configs/acl-transport-2026-11-03.txt) et `--restore` OK ; `cp -a` préserve, `cp -r` perd ACL, setgid et propriétaires ; `tar --acls --xattrs` préserve.

## Mission 4 – sudo
- 90-helios-ops validé par visudo ; julien : restart helios-collect OK, restart sshd refusé, lecture de la télémétrie en tant que helios, journalctl ; nadia hors groupe refusée.
- log_output + sudoreplay : sessions listées et rejouées.
- `sudo vim` → `:!/usr/bin/bash` → uid=0(root). Corrigé par sudoedit (91-nadia-edition) : l'éditeur tourne en nadia (uid=5101).

## Bonus – 5 constats
1. Mot de passe initial identique pour les 4 comptes → `chage -d 0 <user>`.
2. ACL résiduelle user:tarek:rwx sur tournee-j2.csv → `setfacl -x u:tarek …/tournee-j2.csv`.
3. sudoedit de nadia sur transport/* → lister les fichiers nominativement.
4. /srv/helios/depot en 1777 → `chgrp transport` + `chmod 3770` si réservé à l'équipe.
5. SSH root par mot de passe (faible) → `PermitRootLogin prohibit-password`.
