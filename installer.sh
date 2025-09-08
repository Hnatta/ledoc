#!/bin/sh
# installer.sh — pasang paket dari ZIP, timpa file, set izin, restart layanan

set -eu

# ---------- KONFIG UNDUHAN ----------
ZIP_URL="https://github.com/Hnatta/ledoc/archive/refs/heads/main.zip"
ZIP_PATH="/tmp/ledoc-main.zip"
EXTRACT_DIR_GLOB="/tmp/ledoc-*"

# ---------- BERSIHKAN SISA LAMA ----------
rm -f "$ZIP_PATH" 2>/dev/null || true
rm -rf $EXTRACT_DIR_GLOB 2>/dev/null || true

# ---------- UNDUH ZIP ----------
echo "[installer] Download: $ZIP_URL"
if command -v curl >/dev/null 2>&1; then
  curl -fL -o "$ZIP_PATH" "$ZIP_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$ZIP_PATH" "$ZIP_URL"
else
  echo "[ERROR] curl/wget tidak ditemukan." 1>&2
  exit 1
fi

# ---------- EKSRAK ZIP ----------
echo "[installer] Extract: $ZIP_PATH"
if command -v unzip >/dev/null 2>&1; then
  unzip -q "$ZIP_PATH" -d /tmp
else
  echo "[installer] 'unzip' tidak ada. Mencoba pasang (OpenWrt)..."
  if command -v opkg >/dev/null 2>&1; then
    opkg update >/dev/null 2>&1 || true
    opkg install unzip >/dev/null 2>&1 || {
      echo "[ERROR] gagal pasang unzip. Pasang manual: opkg install unzip" 1>&2
      exit 1
    }
    unzip -q "$ZIP_PATH" -d /tmp
  else
    echo "[ERROR] unzip tidak tersedia dan opkg tidak ada." 1>&2
    exit 1
  fi
fi

# Cari direktori sumber hasil ekstrak
SRC_DIR="$(ls -d $EXTRACT_DIR_GLOB 2>/dev/null | head -n1 || true)"
[ -n "$SRC_DIR" ] || { echo "[ERROR] folder ekstrak tidak ditemukan."; exit 1; }

# ---------- DAFTAR FILE ----------
FILES="
files/etc/init.d/hgled.env
files/usr/bin/hgled
files/usr/bin/modem
files/usr/lib/lua/luci/controller/toolsoc
files/usr/lib/lua/luci/view/logoc.htm
files/usr/lib/lua/luci/view/yaml.htm
files/www/cgi-bin/hgled-log.sh
files/www/tinyfm/logoc.html
files/www/tinyfm/yaml.html
"

# ---------- SALIN & TIMPA ----------
echo "[installer] Copy & overwrite files..."
for REL in $FILES; do
  SRC="$SRC_DIR/$REL"
  DST="/$(echo "$REL" | sed 's/^files\///')"
  DDIR="$(dirname "$DST")"
  [ -f "$SRC" ] || { echo "[WARN] skip: $SRC tidak ada"; continue; }
  mkdir -p "$DDIR"
  cp -f "$SRC" "$DST"
  # perbaiki BOM/CRLF khusus CGI agar tidak Exec format error
  case "$DST" in
    /www/cgi-bin/*.sh)
      sed -i '1s/^\xEF\xBB\xBF//' "$DST" 2>/dev/null || true
      sed -i 's/\r$//' "$DST" 2>/dev/null || true
      ;;
  esac
  chmod +x "$DST" 2>/dev/null || true
  echo "  + $DST"
done

# ---------- UHTTPD: CGI SHELL & PREFIX ----------
if command -v uci >/dev/null 2>&1; then
  # tambahkan interpreter .sh jika belum ada
  if ! uci show uhttpd 2>/dev/null | grep -q "main.interpreter=.*\.sh=/bin/sh"; then
    uci add_list uhttpd.main.interpreter='.sh=/bin/sh' 2>/dev/null || true
  fi
  uci set uhttpd.main.cgi_prefix='/cgi-bin'
  uci commit uhttpd
  /etc/init.d/uhttpd restart || true
fi

# ---------- CRON (opsional) ----------
if [ -x /etc/init.d/cron ]; then
  /etc/init.d/cron enable || true
  /etc/init.d/cron restart || true
fi

# ---------- URUTAN ROTOR ----------
echo "[installer] Sequence rotor: off → (sleep 90s) → on"
sleep 2
/usr/bin/hgled -rotor off || true
sleep 90
/usr/bin/hgled -rotor on || true

# ---------- ENABLE SERVICES & RELOAD WEB ----------
/etc/init.d/uhttpd restart || true
/usr/bin/hgled -rotor on || true

# ---------- CLEANUP ----------
echo "[installer] Cleanup ZIP & extracted dir"
rm -f "$ZIP_PATH" 2>/dev/null || true
rm -rf $EXTRACT_DIR_GLOB 2>/dev/null || true

echo "[installer] Selesai. Buka UI (jika ada): http://$(uci get network.lan.ipaddr 2>/dev/null || echo 192.168.1.1)/"
