#!/usr/bin/env bash
# One-command health check for the homelab. Usage: sudo ./healthcheck.sh
# Override the host address with:  HOST=10.0.0.50 ./healthcheck.sh
HOST="${HOST:-10.0.0.105}"
G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'
fails=0; warns=0
ok()   { printf " ${G}✔${N} %s\n" "$1"; }
bad()  { printf " ${R}✘${N} %s\n" "$1"; fails=$((fails+1)); }
warn() { printf " ${Y}!${N} %s\n" "$1"; warns=$((warns+1)); }
hdr()  { printf "\n${B}%s${N}\n" "$1"; }

printf "${B}%s health${N}  %s  (up %s)\n" "$(hostname)" "$(date '+%a %b %d %H:%M')" "$(uptime -p | sed 's/^up //')"

hdr "Containers"
for c in jellyfin npm portainer homepage adguardhome \
         immich_server immich_postgres immich_redis immich_machine_learning; do
  st=$(docker inspect -f '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$c" 2>/dev/null) \
    || { bad "$c: not found"; continue; }
  status=${st%%|*}; health=${st##*|}
  if [ "$status" != "running" ]; then bad "$c: $status"
  elif [ -n "$health" ] && [ "$health" != "healthy" ]; then bad "$c: $health"
  else ok "$c"; fi
done

hdr "Web endpoints"
chk() {
  code=$(curl -sk -o /dev/null -m 5 -w '%{http_code}' "$2")
  if [ "$code" -ge 200 ] 2>/dev/null && [ "$code" -lt 400 ]; then ok "$1 ($code)"; else bad "$1 ($code)  $2"; fi
}
chk "Jellyfin"  "http://$HOST:8096/health"
chk "Immich"    "http://$HOST:2283/api/server/ping"
chk "NPM admin" "http://$HOST:81"
chk "Homepage"  "http://$HOST:3000"
chk "Portainer" "https://$HOST:9443"
chk "AdGuard"   "http://$HOST:3001"

hdr "DNS (AdGuard)"
nslookup -timeout=3 example.com "$HOST" >/dev/null 2>&1 && ok "upstream DNS works" || bad "upstream DNS failed"

hdr "Storage"
if mountpoint -q /srv/data; then
  ok "/srv/data mounted"
else
  bad "/srv/data NOT mounted"
fi
for m in / /srv/data; do
  mountpoint -q "$m" || continue
  u=$(df --output=pcent "$m" | tail -1 | tr -dc '0-9')
  line="$m ${u}% used ($(df -h --output=avail "$m" | tail -1 | tr -d ' ') free)"
  if [ "$u" -ge 95 ]; then bad "$line"; elif [ "$u" -ge 85 ]; then warn "$line"; else ok "$line"; fi
done

hdr "System"
[ -e /dev/dri/renderD128 ] && ok "GPU render device present" || bad "/dev/dri/renderD128 missing"
tailscale status >/dev/null 2>&1 && ok "Tailscale up ($(tailscale ip -4 2>/dev/null | head -1))" || bad "Tailscale down"
mem=$(free | awk '/Mem:/ {printf "%d", $3/$2*100}')
if [ "$mem" -ge 90 ]; then warn "RAM ${mem}% used"; else ok "RAM ${mem}% used"; fi
t=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1)
if [ -n "$t" ]; then
  t=$((t/1000))
  if [ "$t" -ge 85 ]; then bad "CPU temp ${t}C"; elif [ "$t" -ge 75 ]; then warn "CPU temp ${t}C"; else ok "CPU temp ${t}C"; fi
fi
f=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
[ "$f" -eq 0 ] && ok "no failed systemd units" || warn "$f failed systemd unit(s): systemctl --failed"
e=$(journalctl -k --since "24 hours ago" 2>/dev/null | grep -ciE 'usb.*(reset|disconnect)|I/O error|EXT4-fs error')
if [ -z "$e" ]; then warn "kernel log not readable (run with sudo)"
elif [ "$e" -gt 0 ]; then warn "$e drive/USB error lines in last 24h"
else ok "no drive/USB errors in last 24h"; fi

echo
if [ "$fails" -eq 0 ] && [ "$warns" -eq 0 ]; then printf "${G}${B}All good.${N}\n"
elif [ "$fails" -eq 0 ]; then printf "${Y}${B}OK with %s warning(s).${N}\n" "$warns"
else printf "${R}${B}%s problem(s), %s warning(s).${N}\n" "$fails" "$warns"; fi
exit $((fails>0))
