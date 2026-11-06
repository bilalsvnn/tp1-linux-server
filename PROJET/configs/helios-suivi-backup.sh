#!/usr/bin/bash
# helios-suivi-backup.sh - sauvegarde complete du portail de suivi (ACL comprises).
# Sortie : 0 OK · 1 erreur interne · 2 instance deja active · 3 prerequis manquant
set -euo pipefail
IFS=$'\n\t'

readonly DEST=/srv/helios/archives/suivi
readonly KEEP=7
readonly TAG=helios-suivi-backup
readonly CONTENU=(
  srv/helios/suivi
  etc/systemd/system/helios-suivi.service
  etc/systemd/system/helios-suivi-publish.service
  etc/systemd/system/helios-suivi-publish.timer
  etc/systemd/system/helios-suivi-backup.service
  etc/systemd/system/helios-suivi-backup.timer
  etc/sudoers.d/92-helios-suivi
  etc/zabbix/zabbix_agent2.d/helios-suivi.conf
  usr/local/sbin/helios-suivi-publish.sh
  usr/local/sbin/helios-suivi-backup.sh
)
TMP=""

log() { logger -t "$TAG" -p "daemon.${1}" -- "$2" ; }
die() { log err "$1" ; exit "${2:-1}" ; }
cleanup() { local rc=$? ; [[ -n "$TMP" ]] && rm -f -- "$TMP"
            log info "fin d execution rc=${rc}" ; return 0 ; }
trap cleanup EXIT
trap 'die "interrompu par signal" 1' INT TERM

exec 9<"$0"
flock -n 9 || { log warning "une autre instance tourne deja" ; exit 2 ; }

command -v tar >/dev/null || die "tar absent" 3
command -v sha256sum >/dev/null || die "sha256sum absent" 3
[[ -d "$DEST" && -w "$DEST" ]] || die "destination non inscriptible : $DEST" 3
for f in "${CONTENU[@]}" ; do [[ -e "/$f" ]] || die "element absent : /$f" 3 ; done

log info "demarrage"
nom="suivi-$(date +%Y%m%d-%H%M%S).tar.gz"
TMP=$(mktemp "${DEST}/.${nom}.XXXXXX")
# --acls --xattrs : conserve ACL et contexte SELinux (TP2 3.4). rc 1 = fichier modifie pendant la lecture (etat.json)
tar --acls --xattrs --warning=no-file-changed -C / -czpf "$TMP" "${CONTENU[@]}" || { rc=$? ; (( rc == 1 )) || die "echec de tar (rc=${rc})" 1 ; }
mv -f -- "$TMP" "${DEST}/${nom}"
TMP=""
( cd "$DEST" && sha256sum "$nom" > "${nom}.sha256" && sha256sum -c --quiet "${nom}.sha256" ) || die "empreinte invalide" 1
log info "archive ${DEST}/${nom} ($(du -h "${DEST}/${nom}" | cut -f1))"

# Retention : seules les KEEP archives les plus recentes sont conservees
mapfile -t vieilles < <(ls -1t "$DEST"/suivi-*.tar.gz | tail -n +$((KEEP + 1)))
for a in "${vieilles[@]}" ; do rm -f -- "$a" "${a}.sha256" ; done
log info "retention : ${#vieilles[@]} archive(s) supprimee(s), ${KEEP} conservees au maximum"
exit 0
