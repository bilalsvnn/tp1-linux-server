#!/usr/bin/bash
# helios-suivi-publish.sh - publie etat.json a partir de la telemetrie Helios.
# Sortie : 0 OK · 1 erreur interne · 2 instance deja active · 3 prerequis manquant
set -euo pipefail
IFS=$'\n\t'

readonly SRC=/var/lib/helios/telemetry.csv
readonly WWW=/srv/helios/suivi/www
readonly OUT="${WWW}/etat.json"
readonly TAG=helios-suivi-publish
TMP=""

log() { logger -t "$TAG" -p "daemon.${1}" -- "$2" ; }
die() { log err "$1" ; exit "${2:-1}" ; }
cleanup() { local rc=$? ; [[ -n "$TMP" ]] && rm -f -- "$TMP"
            log info "fin d execution rc=${rc}" ; return 0 ; }
trap cleanup EXIT
trap 'die "interrompu par signal" 1' INT TERM

# Verrou exclusif sans ecriture : flock sur le script lui-meme, ouvert en lecture
exec 9<"$0"
flock -n 9 || { log warning "une autre instance tourne deja" ; exit 2 ; }

[[ -r "$SRC" ]] || die "telemetrie illisible : $SRC" 3
[[ -d "$WWW" && -w "$WWW" ]] || die "repertoire publie non inscriptible : $WWW" 3

ligne=$(tail -n 1 -- "$SRC")
[[ "$ligne" =~ ^([0-9T:+-]+),([0-9]+\.[0-9]+),([0-9]+)$ ]] \
  || die "ligne de telemetrie invalide : '${ligne}'" 1
mesure=${BASH_REMATCH[1]} ; charge=${BASH_REMATCH[2]} ; mem=${BASH_REMATCH[3]}
nb=$(wc -l < "$SRC")

# Ecriture atomique : fichier temporaire dans www, puis renommage
TMP=$(mktemp "${WWW}/.etat.json.XXXXXX")
printf '{"genere": "%s", "hote": "%s", "derniere_mesure": "%s", "charge_1min": %s, "mem_dispo_ko": %s, "mesures": %s}\n' \
  "$(date --iso-8601=seconds)" "$HOSTNAME" "$mesure" "$charge" "$mem" "$nb" > "$TMP"
python3 -m json.tool "$TMP" > /dev/null || die "JSON genere invalide" 1
chmod 0640 "$TMP"
mv -f -- "$TMP" "$OUT"
TMP=""
log info "etat.json publie (${nb} mesures, charge ${charge})"
exit 0
