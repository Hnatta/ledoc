cat > /tmp/installer.sh <<'EOF'
#!/bin/sh
# installer.sh — pasang dari ZIP, timpa file, chmod +x semua, tanam rc.local, start hgled & rotor
set -eu

ZIP_URL="${ZIP_URL:-https://github.com/Hnatta/ledoc/archive/refs/heads/main.zip}"
ZIP_PATH="${ZIP_PATH:-/tmp/ledoc-main.zip}"
EXTRACT_DIR_GLOB="${EXTRACT_DIR_GLOB:-/tmp/ledoc-*}"

# bersih
rm -f "$ZIP_PATH" 2>/dev/null || true
rm -rf $EXTRACT_DIR_GLOB 2>/dev/null || true

# unduh
echo "[installer] Download: $ZIP_URL"
if command -v curl >/dev/null 2>&1; then
  curl -fL -o "$ZIP_PATH" "$ZIP_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$ZIP_PATH" "$ZIP_URL"
else
  echo "[ERROR] butuh curl atau wget" >&2; exit 1
fi

# ekstrak
echo "[installer] Extract: $ZIP_PATH"
if ! command -v unzip >/dev/null 2>&1; then
  opkg update >/dev/null 2>&1 || true
  opkg install unzip >/dev/null 2>&1 || { echo "[ERROR] gagal pasang unzip"; exit 1; }
fi
unzip -q "$ZIP_PATH" -d /tmp
SRC_DIR="$(ls -d $EXTRACT_DIR_GLOB 2>/dev/null | head -n1 || true)"
[ -n "$SRC_DIR" ] || { echo "[ERROR] extract dir not found"; exit 1; }

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

echo "[installer] Copy & overwrite files..."
for REL in $FILES; do
  SRC="$SRC_DIR/$REL"
  DST="/$(printf '%s' "$REL" | sed 's/^files\///')"
  DDIR="$(dirname "$DST")"
  if [ ! -f "$SRC" ]; then echo "[WARN] skip: $SRC"; continue; fi
  mkdir -p "$DDIR"
  cp -f "$SRC" "$DST"

  # normalisasi (anti Exec format error)
  sed -i '1s/^\xEF\xBB\xBF//' "$DST" 2>/dev/null || true
  sed -i 's/\r$//' "$DST" 2>/dev/null || true
  case "$DST" in
    /usr/bin/hgled|/usr/bin/modem|/www/cgi-bin/*.sh)
      grep -q '^#!' "$DST" || sed -i '1i #!/bin/sh' "$DST"
      ;;
  esac
  chmod +x "$DST" 2>/dev/null || true
  echo "  + $DST"
done

# uhttpd CGI
if command -v uci >/dev/null 2>&1; then
  uci add_list uhttpd.main.interpreter='.sh=/bin/sh' 2>/dev/null || true
  uci set uhttpd.main.cgi_prefix='/cgi-bin'
  uci commit uhttpd
  /etc/init.d/uhttpd restart || true
fi

# rc.local boot sequence
RC=/etc/rc.local
if [ ! -f "$RC" ]; then echo "#!/bin/sh" > "$RC"; echo "exit 0" >> "$RC"; chmod +x "$RC"; fi
sed -i "/^# >>> hgled boot start/,/^# >>> hgled boot end/d" "$RC"
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

# urutan rotor + start LED
echo "[installer] Sequence rotor: off → (sleep 90s) → on"
sleep 2
/usr/bin/hgled -s || true
/usr/bin/hgled -rotor off || true
sleep 90
/usr/bin/hgled -rotor on || true
/usr/bin/hgled -r || true
/usr/bin/hgled -rotor on || true

# reload web & cleanup
(/etc/init.d/uhttpd restart || true) >/dev/null 2>&1
echo "[installer] Cleanup"
rm -f "$ZIP_PATH" 2>/dev/null || true
rm -rf $EXTRACT_DIR_GLOB 2>/dev/null || true

echo "[installer] Selesai."
EOF
sh /tmp/installer.sh
