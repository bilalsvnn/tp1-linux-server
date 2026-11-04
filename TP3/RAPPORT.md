# TP3 – Sécurisation d'un serveur Linux (Hélios)
Bilal Chaybouti – BTC2 IPSSI Lille – 04/11/2026 – srv-core (cible) / srv-edge (attaquant)

## Interface → zone → politique
| Interface | Zone | Politique | Justification |
|---|---|---|---|
| enp0s3 (NAT) | drop | rien n'entre | Exposée vers Internet, aucun service publié |
| enp0s8 (admin) | work | SSH 2242 seul, source 192.168.56.0/24, 3/m (rafale 6), journalisé SSH-NEW ; 10051 rejeté | Réseau d'administration |
| bond0 (métier) | internal | 2242 + 10051 (Zabbix) | Réseau de confiance, supervision |
| bond0.42 (VLAN transport) | internal | idem | Même niveau de confiance |
Zone par défaut : **drop**. ipset `helios-blacklist` (drop) sur work et internal. Zone écrite dans le profil NetworkManager (`connection.zone`).

## crypto-policies et sshd_config
`sshd_config` inclut `sshd_config.d/*.conf` par ordre alphabétique ; `50-redhat.conf` inclut la politique système (`opensshserver.config`). sshd retient la **première valeur lue** : une directive Ciphers/KexAlgorithms/MACs n'agit que si elle est lue avant 50-redhat.conf, et hors bloc Match. D'où `05-helios-crypto.conf`. Approche recommandée : `update-crypto-policies --set DEFAULT:NO-SHA1` (s'applique à tout le système). Le même mécanisme expliquait une faille trouvée : `01-permitrootlogin.conf` (créé par l'installeur) imposait `PermitRootLogin yes` avant notre drop-in → supprimé, `sshd -T` → `permitrootlogin no`.

## Trois conséquences d'un changement de port SSH sur RHEL 9
1. sshd : `Port 2242` (+ ListenAddress).
2. SELinux : `semanage port -a -t ssh_port_t -p tcp 2242`, sinon sshd ne peut pas se lier au port.
3. Pare-feu : ouvrir 2242 et retirer le service ssh/22.
(Constat supplémentaire : avec ListenAddress et wait-online masqué, sshd échouait au boot → `net.ipv4.ip_nonlocal_bind=1`.)

## Sept tests SSH (depuis srv-edge)
1 port 22 : No route to host · 2 sysops par clé : OK · 3 root : Permission denied (publickey) · 4 mot de passe : refusé · 5 nadia : refusée · 6 tunnel 10051 : administratively prohibited · 7 KEX SHA-1 : no matching key exchange method.

## Cinq requêtes d'investigation
| Requête | Ce qu'elle révèle |
|---|---|
| `journalctl _SYSTEMD_UNIT=sshd.service -g 'Invalid user\|Failed\|Accepted'` | Connexions acceptées avec l'empreinte de la clé utilisée (srv-edge vs hôte) ; tentatives d'utilisateurs invalides |
| `journalctl --facility=authpriv --since today` | Fil d'une session : SSH sysops → session PAM → `sudo -i` vers root |
| `journalctl -t sudo -o json-pretty` | Champs complets dont `_AUDIT_LOGINUID=5104` : identité réelle derrière root |
| `journalctl -b -1 -p err` | Erreurs du boot précédent, lisibles grâce à la persistance |
| `lastb ; last -F ; lslogins` | Échecs de nadia, sessions « crash » (arrêts brutaux), mots de passe root/bilel jamais changés, expiration audit-ext |

## journald, auditd, détection
- journald persistant : `journalctl --list-boots` → 2 démarrages. `Seal=yes` nécessite `journalctl --setup-keys` (non fait).
- auditd : 14 règles ; `ausearch -k privesc -i` montre `auid=sysops` derrière les commandes root ; événement `sudoers` capté.
- helios-watch-auth.sh + timer (2 min) : > 5 échecs en 10 min → ipset. Attaque de srv-edge → `BLOCAGE 192.168.56.11`, ipset peuplé, srv-edge en TIMEOUT. Bug corrigé (`IFS=" " read`). Le pare-feu limitant les rafales, il a fallu des tentatives espacées : les deux protections se complètent.

Non réalisé : mission bonus, nmap « après ».
