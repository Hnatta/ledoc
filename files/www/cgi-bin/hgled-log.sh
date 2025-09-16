#!/bin/sh
# /www/cgi-bin/hgled-log.sh
# Output: application/json { "log":[...] }

# === konfigurasi (bisa override via ENV/uci/run cmd) ===
LOG_LINES="${LOG_LINES:-100}"

# --- helper JSON escape (sederhana) ---
jesc() { sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g'; }

# --- ambil log ---
if command -v logread >/dev/null 2>&1; then
  LOG_RAW="$(logread 2>/dev/null | grep -E 'hgled' | tail -n "$LOG_LINES")"
else
  LOG_RAW="logread not found"
fi

# --- cetak JSON ---
echo "Content-Type: application/json"
echo ""
printf '{ "log":['
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
printf '] }\n'
