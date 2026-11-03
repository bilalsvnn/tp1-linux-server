# TP1 – systemd, réseau avancé et automatisation (projet Hélios)

Bilal Chaybouti – Bachelor Informatique 2e année (BTC2), IPSSI Lille – Administration d'un Linux Server

Environnement : VirtualBox, Rocky Linux 9.8 – `srv-core` (192.168.56.10) et `srv-edge` (192.168.56.11).

## Contenu
| Chemin | Description |
|---|---|
| [`RAPPORT.md`](RAPPORT.md) | Synthèse : mesures, critères, tableau cron vs timer |
| [`CR_TP1_Linux_Bilal_Chaybouti.pdf`](CR_TP1_Linux_Bilal_Chaybouti.pdf) | Compte rendu complet avec captures |
| [`configs/`](configs) | Units systemd, drop-in, scripts, profil bond0 |
| [`captures/`](captures) | Captures d'écran et graphiques de boot (SVG) |

## Résultats
- Boot : 1 min 43,8 s → 21,6 s
- `systemd-analyze security helios-collect` : 5.3 MEDIUM → 0.6 SAFE
- Bascule du bond active-backup : 2 ICMP perdus
- VLAN 42 + routage par source (table `transport`) persistants après reboot
- Timer d'archivage quotidien à 02:30, path unit en bonus
