#!/usr/bin/bash
# helios-watch-auth.sh - bloque les sources d'echecs SSH repetes.
# Sortie : 0 nominal · 2 instance deja active
set -euo pipefail
IFS=$'\n\t'

readonly TAG=helios-watch-auth
readonly WINDOW='-10min'
readonly THRESHOLD=5
readonly IPSET=helios-blacklist
readonly LOCK=/run/lock/helios-watch-auth.lock
readonly STATE=/var/lib/helios/blocked.txt
readonly WHITELIST=(192.168.56.1 127.0.0.1)

log() { logger -t "$TAG" -p "authpriv.${1}" -- "$2" ; }

exec 9>"$LOCK"
flock -n 9 || { log warning "une autre instance tourne deja" ; exit 2 ; }
touch "$STATE"

# Adresses ayant echoue (utilisateur invalide ou authentification ratee)
ips=$(journalctl -u sshd --since "$WINDOW" --no-pager -o cat \
      | grep -E 'Invalid user|Failed (password|publickey)' \
      | grep -oE 'from ([0-9]{1,3}\.){3}[0-9]{1,3}' \
      | awk '{print $2}' | sort | uniq -c || true)

nb=0
while IFS=" " read -r count ip ; do
  [[ -z "${ip:-}" ]] && continue
  (( count > THRESHOLD )) || continue
  if printf '%s\n' "${WHITELIST[@]}" | grep -qx "$ip" ; then
    log info "${ip} : ${count} echecs mais en liste blanche, ignore" ; continue
  fi
  if grep -qx "$ip" "$STATE" || firewall-cmd -q --ipset="$IPSET" --query-entry="$ip" ; then
    continue                                    # idempotence : deja bloque, pas de 2e alerte
  fi
  firewall-cmd -q --ipset="$IPSET" --add-entry="$ip"
  echo "$ip" >> "$STATE"
  log warning "BLOCAGE ${ip} : ${count} echecs SSH sur ${WINDOW#-}"
  nb=$((nb + 1))
done <<< "$ips"

log info "analyse terminee, ${nb} nouvelle(s) adresse(s) bloquee(s)"
exit 0
