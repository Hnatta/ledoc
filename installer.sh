cat > /tmp/installer.sh <<'EOF'
#!/bin/sh
# installer.sh — pasang dari ZIP, timpa file, chmod +x semua, tanam rc.local, start hgled & rotor

set -eu

# ---------- KONFIG ----------
ZIP_URL="${ZIP_URL:-https://github.com/Hnatta/ledoc/archive/refs/heads/main.zip}"
ZIP_PATH="${ZIP_PATH:-/tmp/ledoc-main.zip}"
EXTRACT_DIR_GLOB="${EXTRACT_DIR_GLOB:-/tmp/ledoc-*}"

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
  echo "[ERROR] butuh curl atau wget" >&2
  exit 1
fi

# ---------- EKSRAK ZIP ----------
echo "[installer] Extract: $ZIP_PATH"
if ! command -v unzip >/dev/null 2>&1; then
  echo "[installer] memasang unzip (OpenWrt) ..."
  opkg update >/dev/null 2>&1 || true
  opkg install unzip >/dev/null 2>&1 || { echo "[ERROR] gagal pasang unzip"; exit 1; }
fi
unzip -q "$ZIP_PATH" -d /tmp
SRC_DIR="$(ls -d $EXTRACT_DIR_GLOB 2>/dev/null | head -n1 || true)"
[ -n "$SRC_DIR" ] || { echo "[ERROR] folder ekstrak tidak ditemukan"; exit 1; }

# ---------- DAFTAR FILE DARI ZIP ----------
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

# ---------- COPY & TIMPA + NORMALISASI + CHMOD +x ----------
echo "[installer] Copy & overwrite files..."
for REL in $FILES; do
  SRC="$SRC_DIR/$REL"
  DST="/$(printf '%s' "$REL" | sed 's/^files\///')"
  DDIR="$(dirname "$DST")"
  if [ ! -f "$SRC" ]; then
    echo "[WARN] skip (tak ada): $SRC"
    continue
  fi
  mkdir -p "$DDIR"
  cp -f "$SRC" "$DST"

  # Hapus BOM & CRLF agar tidak 'Exec format error'
  sed -i '1s/^\xEF\xBB\xBF//' "$DST" 2>/dev/null || true
  sed -i 's/\r$//' "$DST" 2>/dev/null || true

  # Pastikan shebang untuk skrip shell
  case "$DST" in
    /usr/bin/hgled|/usr/bin/modem|/www/cgi-bin/*.sh)
      grep -q '^#!' "$DST" || sed -i '1i #!/bin/sh' "$DST"
      ;;
  esac

  # CHMOD +x semua file (sesuai permintaan)
  chmod +x "$DST" 2>/dev/null || true

  echo "  + $DST"
done

# (opsional) duplikasi env ke /etc/hgled.env agar mudah dibaca script
if [ -f /etc/init.d/hgled.env ] && [ ! -f /etc/hgled.env ]; then
  cp -f /etc/init.d/hgled.env /etc/hgled.env || true
fi

# ---------- UHTTPD: ENABLE CGI ----------
if command -v uci >/dev/null 2>&1; then
  if ! uci show uhttpd 2>/dev/null | grep -q "main.interpreter=.*\.sh=/bin/sh"; then
    uci add_list uhttpd.main.interpreter='.sh=/bin/sh' 2>/dev/null || true
  fi
  uci set uhttpd.main.cgi_prefix='/cgi-bin'
  uci commit uhttpd
  /etc/init.d/uhttpd restart || true
fi

# ---------- TANAM RC.LOCAL (BOOT SEQUENCE) ----------
RC=/etc/rc.local
if [ ! -f "$RC" ]; then
  echo "#!/bin/sh" > "$RC"
  echo "exit 0"   >> "$RC"
  chmod +x "$RC"
fi
# hapus blok lama bila ada
sed -i "/^# >>> hgled boot start/,/^# >>> hgled boot end/d" "$RC"
# sisipkan blok baru sebelum exit 0
awk '
BEGIN{printed=0}
/^exit 0$/ && !printed{
  print "# >>> hgled boot start"
  print "sleep 2"
  print "/usr/bin/hgled -s || true"
  print "/usr/bin/hgled -rotor off || true"
  print "sleep 90"
  print "/usr/bin/hgled -rotor on || true"
  print "# >>> hgled boot end"
  printed=1
}
{print}
END{
  if(!printed){
    print "# >>> hgled boot start"
    print "sleep 2"
    print "/usr/bin/hgled -s || true"
    print "/usr/bin/hgled -rotor off || true"
    print "sleep 90"
    print "/usr/bin/hgled -rotor on || true"
    print "# >>> hgled boot end"
    print "exit 0"
  }
}' "$RC" > /tmp/rc.local.new && mv /tmp/rc.local.new "$RC" && chmod +x "$RC"

# ---------- URUTAN ROTOR (SESUAI PERMINTAAN) ----------
echo "[installer] Sequence rotor: off → (sleep 90s) → on"
sleep 2
/usr/bin/hgled -s || true
/usr/bin/hgled -rotor off || true
sleep 90
/usr/bin/hgled -rotor on || true

# ---------- SETELAH INSTAL: START LED & PASTIKAN ROTOR ON ----------
/usr/bin/hgled -r || true
/usr/bin/hgled -rotor on || true

# ---------- RELOAD WEB (JAGA-JAGA) ----------
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

# ---------- BERSIH-BERSIH ----------
echo "[installer] Cleanup ZIP & extracted dir"
rm -f "$ZIP_PATH" 2>/dev/null || true
rm -rf $EXTRACT_DIR_GLOB 2>/dev/null || true

echo "[installer] Selesai."
EOF
sh /tmp/installer.sh
