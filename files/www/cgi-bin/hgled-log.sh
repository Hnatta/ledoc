#!/bin/sh
# /www/cgi-bin/hgled-log.sh
# Output: application/json { "log":[...], "latencies": { "SGR_ACTIVE":123, ... } }

# === konfigurasi (bisa override via ENV/uci/run cmd) ===
CTRL="${CTRL:-http://127.0.0.1:9090}"
SECRET="${SECRET:-12345}"
GROUPS="${GROUPS:-SGR_ACTIVE IDN_ACTIVE WRD_ACTIVE}"
PING_URL="${PING_URL:-https://www.gstatic.com/generate_204}"
TIMEOUT_MS="${TIMEOUT_MS:-3000}"
LOG_LINES="${LOG_LINES:-100}"

# --- helper JSON escape (sederhana) ---
jesc() { sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g'; }

# --- ambil log ---
if command -v logread >/dev/null 2>&1; then
  LOG_RAW="$(logread 2>/dev/null | grep -E 'hgled' | tail -n "$LOG_LINES")"
else
  LOG_RAW="logread not found"
fi

# --- ambil latency per grup dari Clash: /proxies/<GROUP>/delay ---
latencies_json=""
for g in $GROUPS; do
  enc="$(printf '%s' "$g" | sed 's/ /%20/g')"
  maxs=$(( (TIMEOUT_MS/1000) + 2 ))
  if [ -n "$SECRET" ]; then
    out="$(curl -sS --max-time "$maxs" -H "Authorization: Bearer $SECRET" -G \
      --data-urlencode "url=$PING_URL" \
      --data-urlencode "timeout=$TIMEOUT_MS" \
      "$CTRL/proxies/$enc/delay" 2>/dev/null || true)"
  else
    out="$(curl -sS --max-time "$maxs" -G \
      --data-urlencode "url=$PING_URL" \
      --data-urlencode "timeout=$TIMEOUT_MS" \
      "$CTRL/proxies/$enc/delay" 2>/dev/null || true)"
  fi
  delay="$(printf '%s' "$out" | sed -n 's/.*"delay":\([0-9][0-9]*\).*/\1/p')"
  [ -z "$delay" ] && delay="null"
  [ -n "$latencies_json" ] && latencies_json="$latencies_json, "
  latencies_json="$latencies_json\"$g\": $delay"
done

# --- cetak JSON ---
echo "Content-Type: application/json"
echo ""
printf '{ "log":['
# print log line-by-line sebagai array JSON
IFS='
'
first=1
for L in $LOG_RAW; do
  esc_line="$(printf '%s' "$L" | jesc)"
  if [ $first -eq 1 ]; then
    printf '"%s"' "$esc_line"; first=0
  else
    printf ', "%s"' "$esc_line"
  fi
done
printf '], "latencies":{ %s } }\n' "$latencies_json"
