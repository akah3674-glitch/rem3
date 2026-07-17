#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   NRO Private Server – Termux Auto Setup (Độc lập)              ║
# ║   APK: Google Drive  |  Server: Java + MariaDB                  ║
# ║   Chạy: bash nro_setup.sh                                       ║
# ╚══════════════════════════════════════════════════════════════════╝

# KHÔNG dùng set -e để tránh crash ngoài ý muốn

# ─── màu ──────────────────────────────────────────────────────────
R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m'
B='\033[1;34m' C='\033[1;36m' W='\033[1;37m' N='\033[0m'

ok()  { echo -e "${G}[✓]${N} $*"; }
err() { echo -e "${R}[✗]${N} $*"; }
inf() { echo -e "${B}[i]${N} $*"; }
wrn() { echo -e "${Y}[!]${N} $*"; }

# ─── cấu hình ─────────────────────────────────────────────────────
NRO_HOME="$HOME/nro-server"
APK_DIR="$HOME/storage/downloads"
APK_OUT="$APK_DIR/NRO_Local.apk"
GDRIVE_ID="19whOmyWZ3EMIWZ3g6e-fejRkfeH7_6b5"
PATCH_IP="127.0.0.1"
PATCH_PORT="14445"
DB_NAME="nro"
DB_USER="root"
DB_PASS=""

KEYSTORE="$HOME/.nro_sign.keystore"
KEY_ALIAS="nrosign"
KEY_PASS="nro12345"

SETUP_FLAG="$NRO_HOME/.setup_done"

banner() {
  clear
  echo -e "${C}"
  echo "  ███╗   ██╗██████╗  ██████╗ "
  echo "  ████╗  ██║██╔══██╗██╔═══██╗"
  echo "  ██╔██╗ ██║██████╔╝██║   ██║"
  echo "  ██║╚██╗██║██╔══██╗██║   ██║"
  echo "  ██║ ╚████║██║  ██║╚██████╔╝"
  echo "  ╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ "
  echo -e "${Y}    Ngọc Rồng Online – Private Server (Termux)${N}"
  echo -e "${G}  ══════════════════════════════════════════════${N}"
  echo ""
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 1: Cài packages
# ══════════════════════════════════════════════════════════════════
step_packages() {
  inf "Cập nhật pkg list..."
  pkg update -y 2>/dev/null || true

  inf "Cài packages (có thể mất vài phút)..."
  pkg install -y curl wget python python-pip openjdk-17 mariadb openssl zip unzip 2>&1 | grep -E "^(Setting up|Err|E:)" || true

  inf "Cài pip packages (gdown)..."
  pip3 install -q gdown 2>/dev/null || pip install -q gdown 2>/dev/null || true

  ok "Packages xong!"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 2: Setup MariaDB
# ══════════════════════════════════════════════════════════════════
step_mariadb() {
  mkdir -p "$NRO_HOME"

  # Init data dir nếu chưa có
  if [[ ! -d "$PREFIX/var/lib/mysql/mysql" ]]; then
    inf "Khởi tạo MariaDB data dir..."
    mysql_install_db 2>&1 | tail -5 || true
    ok "MariaDB init xong"
  else
    ok "MariaDB đã init trước đó"
  fi

  # Kill instance cũ nếu có
  pkill mysqld 2>/dev/null || true
  pkill mysqld_safe 2>/dev/null || true
  sleep 2

  # Start MariaDB
  inf "Khởi động MariaDB..."
  mysqld_safe --user="$(whoami)" 2>/dev/null &
  MYSQLD_BG=$!
  disown $MYSQLD_BG 2>/dev/null || true

  # Chờ tối đa 30 giây
  local i=0
  local ok_flag=0
  while [[ $i -lt 30 ]]; do
    sleep 1
    i=$((i+1))
    if mysqladmin -u root ping 2>/dev/null | grep -q "alive"; then
      ok_flag=1
      break
    fi
    # Thử cách khác
    if mysql -u root -e "SELECT 1;" 2>/dev/null | grep -q "1"; then
      ok_flag=1
      break
    fi
    echo -ne "  Chờ MariaDB... ${i}s\r"
  done
  echo ""

  if [[ $ok_flag -eq 0 ]]; then
    wrn "MariaDB chưa phản hồi sau 30s — thử tiếp..."
    # Có thể đã chạy nhưng socket khác
    if mysql -u root -e "SELECT 1;" 2>/dev/null; then
      ok_flag=1
    fi
  fi

  if [[ $ok_flag -eq 1 ]]; then
    ok "MariaDB đang chạy!"
  else
    err "MariaDB không khởi động được"
    wrn "Tiếp tục... (có thể setup DB sau)"
    return 0
  fi

  # Tạo database
  inf "Tạo database '$DB_NAME'..."
  mysql -u root 2>/dev/null << SQLEOF || true
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'root'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'root'@'127.0.0.1';
FLUSH PRIVILEGES;
SQLEOF

  # Schema
  mysql -u root "$DB_NAME" 2>/dev/null << 'SQLEOF' || true
CREATE TABLE IF NOT EXISTS account (
  id          INT PRIMARY KEY AUTO_INCREMENT,
  username    VARCHAR(50) UNIQUE NOT NULL,
  password    VARCHAR(100) NOT NULL,
  email       VARCHAR(100),
  status      TINYINT DEFAULT 1,
  created_at  DATETIME DEFAULT NOW()
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS nro_character (
  id          INT PRIMARY KEY AUTO_INCREMENT,
  account_id  INT,
  name        VARCHAR(50) UNIQUE NOT NULL,
  level       INT DEFAULT 1,
  exp         BIGINT DEFAULT 0,
  gold        BIGINT DEFAULT 0,
  gem         INT DEFAULT 0,
  map_id      INT DEFAULT 1,
  pos_x       INT DEFAULT 0,
  pos_y       INT DEFAULT 0,
  created_at  DATETIME DEFAULT NOW()
) ENGINE=InnoDB;
SQLEOF

  ok "Database '$DB_NAME' sẵn sàng"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 3: Tải APK từ Google Drive
# ══════════════════════════════════════════════════════════════════
step_download_apk() {
  local rar_file="/tmp/nro_drive.rar"
  local apk_raw="/tmp/nro_original.apk"

  rm -f "$rar_file" "$apk_raw" 2>/dev/null || true

  # Cài p7zip để giải nén RAR
  inf "Cài p7zip (giải nén RAR)..."
  pkg install -y p7zip 2>/dev/null | grep "Setting up" || true

  # ── Tải file RAR từ Drive ──
  # URL trực tiếp đã kiểm tra - hoạt động ổn định
  local DRIVE_URL="https://drive.usercontent.google.com/download?id=${GDRIVE_ID}&export=download&authuser=0&confirm=t"

  inf "Tải file từ Google Drive (~2.2GB, RAR)..."
  wrn "Lưu ý: file lớn ~2.2GB, cần đủ dung lượng và mạng ổn định"
  echo ""

  curl -L -A "Mozilla/5.0" \
    --retry 3 --retry-delay 5 \
    --continue-at - \
    --progress-bar \
    "$DRIVE_URL" \
    -o "$rar_file" 2>&1

  local sz; sz=$(stat -c%s "$rar_file" 2>/dev/null || echo 0)
  if [[ "$sz" -lt 1000000 ]]; then
    err "Tải thất bại hoặc file không đúng (${sz} bytes)"
    # Thử wget
    inf "Thử lại bằng wget..."
    wget --continue --show-progress -q \
      "$DRIVE_URL" \
      -O "$rar_file" 2>/dev/null || true
    sz=$(stat -c%s "$rar_file" 2>/dev/null || echo 0)
  fi

  if [[ "$sz" -lt 1000000 ]]; then
    err "Tải Drive thất bại! (${sz} bytes)"
    return 1
  fi

  ok "Tải xong: $(du -h "$rar_file" | cut -f1)"

  # ── Giải nén RAR ──
  inf "Giải nén RAR..."
  mkdir -p /tmp/nro_extract
  7z x -y "$rar_file" -o/tmp/nro_extract 2>&1 | tail -5 || true

  # Tìm APK bên trong
  local found_apk
  found_apk=$(find /tmp/nro_extract -name "*.apk" 2>/dev/null | head -1)

  if [[ -z "$found_apk" ]]; then
    # Thử tìm nested RAR/ZIP
    local nested
    nested=$(find /tmp/nro_extract -name "*.rar" -o -name "*.zip" 2>/dev/null | head -1)
    if [[ -n "$nested" ]]; then
      inf "Giải nén lớp 2: $(basename $nested)..."
      7z x -y "$nested" -o/tmp/nro_extract2 2>&1 | tail -3 || true
      found_apk=$(find /tmp/nro_extract2 -name "*.apk" 2>/dev/null | head -1)
    fi
  fi

  if [[ -z "$found_apk" ]]; then
    err "Không tìm thấy file APK trong RAR!"
    inf "Nội dung giải nén:"
    find /tmp/nro_extract -type f 2>/dev/null | head -20
    return 1
  fi

  cp "$found_apk" "$apk_raw"
  ok "APK: $(basename $found_apk) ($(du -h "$apk_raw" | cut -f1))"
  echo "$apk_raw"
}

_apk_check() {
  local f="$1"
  [[ ! -f "$f" ]] && return 1
  local sz; sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
  [[ "$sz" -lt 1000000 ]] && return 1
  return 0
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 4: Patch APK (IP → 127.0.0.1)
# ══════════════════════════════════════════════════════════════════
step_patch_apk() {
  local apk_in="$1"
  local apk_out="/tmp/nro_patched.apk"

  inf "Patch IP → ${PATCH_IP}:${PATCH_PORT} trong APK..."

  python3 << PYEOF
import sys, zipfile, re, os

apk_in   = "$apk_in"
apk_out  = "$apk_out"
new_ip   = "$PATCH_IP"
new_port = $PATCH_PORT

META_PATHS = [
    "assets/bin/Data/Managed/Metadata/global-metadata.dat",
    "assets/bin/Data/il2cpp_data/Metadata/global-metadata.dat",
]

def find_meta(zin):
    names = zin.namelist()
    for p in META_PATHS:
        if p in names:
            return p
    cands = [n for n in names if "global-metadata" in n.lower()]
    return cands[0] if cands else None

def patch_data(data, new_ip, new_port):
    # Pattern: <prefix>:<old_ip>:<port>:<suffix>
    def repl(m):
        orig = m.group(0)
        new_part = m.group(1) + new_ip.encode() + b':' + str(new_port).encode() + m.group(4)
        if len(new_part) <= len(orig):
            new_part += b'\\x00' * (len(orig) - len(new_part))
            return new_part
        return orig

    data2 = re.sub(
        rb'([A-Za-z]{2,20}:)([\d\.a-z\-]+)(:\d{4,5})(:[\d,]*)',
        repl, data
    )
    if data2 != data:
        return data2, True

    # Fallback: known IP strings
    known = [
        b"dragonboy.vn", b"server.dragonboy.vn", b"ngocrongonline.vn",
        b"103.27.", b"103.57.", b"171.244.", b"27.74.", b"45.119.",
    ]
    for old in known:
        if old in data:
            new = new_ip.encode()
            if len(new) < len(old):
                new += b'\\x00' * (len(old) - len(new))
            elif len(new) > len(old):
                continue
            return data.replace(old, new, 1), True

    return data, False

try:
    with zipfile.ZipFile(apk_in, 'r') as zin:
        meta_path = find_meta(zin)
        if not meta_path:
            print("[!] Không tìm thấy metadata — ghi APK không patch")
            meta_path = None
            meta_data = b""
        else:
            print(f"  Metadata: {meta_path}")
            meta_data = zin.read(meta_path)

    if meta_path:
        patched_data, ok = patch_data(meta_data, new_ip, new_port)
        print(f"  Patch: {'OK' if ok else 'KHÔNG tìm được IP cũ'}")
    else:
        patched_data = b""
        ok = False

    with zipfile.ZipFile(apk_in, 'r') as zin, \
         zipfile.ZipFile(apk_out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zout:
        for item in zin.infolist():
            raw = zin.read(item.filename)
            if meta_path and item.filename == meta_path:
                zout.writestr(item, patched_data)
            else:
                zout.writestr(item, raw)

    print(f"[OK] APK ghi xong: {apk_out}")
except Exception as e:
    print(f"[ERR] {e}")
    sys.exit(1)
PYEOF

  if [[ $? -ne 0 ]] || [[ ! -f "$apk_out" ]]; then
    err "Patch APK thất bại!"
    return 1
  fi

  ok "Patch xong"
  echo "$apk_out"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 5: Ký APK + lưu ra Downloads
# ══════════════════════════════════════════════════════════════════
step_sign_apk() {
  local apk_in="$1"

  # Tạo keystore
  if [[ ! -f "$KEYSTORE" ]]; then
    inf "Tạo keystore..."
    keytool -genkeypair -v \
      -keystore "$KEYSTORE" \
      -alias "$KEY_ALIAS" \
      -keyalg RSA -keysize 2048 -validity 9999 \
      -dname "CN=NRO,O=NRO,C=VN" \
      -storepass "$KEY_PASS" -keypass "$KEY_PASS" 2>/dev/null && ok "Keystore OK" || wrn "Keystore lỗi nhỏ"
  fi

  inf "Ký APK..."
  jarsigner \
    -keystore "$KEYSTORE" \
    -storepass "$KEY_PASS" -keypass "$KEY_PASS" \
    -digestalg SHA-256 -sigalg SHA256withRSA \
    "$apk_in" "$KEY_ALIAS" 2>/dev/null && ok "Ký OK" || wrn "jarsigner có cảnh báo (bỏ qua)"

  # Lưu ra Downloads
  termux-setup-storage 2>/dev/null || true
  mkdir -p "$APK_DIR"
  cp "$apk_in" "$APK_OUT"
  ok "APK đã lưu → $APK_OUT"
}

# ══════════════════════════════════════════════════════════════════
# Tạo launcher start/stop
# ══════════════════════════════════════════════════════════════════
step_create_launcher() {
  mkdir -p "$NRO_HOME/bin"

  cat > "$NRO_HOME/bin/start.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
NRO_HOME="$HOME/nro-server"
G='\033[1;32m' R='\033[1;31m' C='\033[1;36m' Y='\033[1;33m' N='\033[0m'
ok()  { echo -e "${G}[✓]${N} $*"; }
err() { echo -e "${R}[✗]${N} $*"; }
inf() { echo -e "${C}[i]${N} $*"; }

echo -e "${Y}══════ NRO Server Launcher ══════${N}"

# Start MariaDB nếu chưa chạy
if ! mysqladmin -u root ping 2>/dev/null | grep -q "alive"; then
  inf "Khởi động MariaDB..."
  mysqld_safe --user="$(whoami)" 2>/dev/null &
  disown
  sleep 4
fi
mysqladmin -u root ping 2>/dev/null | grep -q "alive" && ok "MariaDB: Running" || err "MariaDB: Lỗi"

# Tìm và chạy server JAR
JAR_GAME=$(find "$NRO_HOME" -maxdepth 2 \( -name "Srcgame.jar" -o -name "game.jar" -o -name "server.jar" \) 2>/dev/null | head -1)
JAR_LOGIN=$(find "$NRO_HOME" -maxdepth 2 \( -name "ServerLogin.jar" -o -name "login.jar" \) 2>/dev/null | head -1)

if [[ -n "$JAR_GAME" ]]; then
  inf "Start: $(basename $JAR_GAME)"
  cd "$(dirname $JAR_GAME)" && java -jar "$JAR_GAME" &
  disown
  ok "Game Server: PID $!"
else
  err "Chưa có server JAR!"
  echo "  → Copy Srcgame.jar vào: $NRO_HOME/"
fi

if [[ -n "$JAR_LOGIN" ]]; then
  inf "Start: $(basename $JAR_LOGIN)"
  cd "$(dirname $JAR_LOGIN)" && java -jar "$JAR_LOGIN" &
  disown
  ok "Login Server: Started"
fi

echo ""
ok "Mở APK: Downloads/NRO_Local.apk để chơi!"
EOF
  chmod +x "$NRO_HOME/bin/start.sh"

  cat > "$NRO_HOME/bin/stop.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f "Srcgame.jar"   2>/dev/null && echo "[✓] Game server dừng"   || true
pkill -f "ServerLogin.jar" 2>/dev/null && echo "[✓] Login server dừng" || true
mysqladmin -u root shutdown 2>/dev/null && echo "[✓] MariaDB dừng"     || true
EOF
  chmod +x "$NRO_HOME/bin/stop.sh"

  ok "Launcher: $NRO_HOME/bin/start.sh"
}

# ══════════════════════════════════════════════════════════════════
# ADMIN MENU
# ══════════════════════════════════════════════════════════════════
_mysql() { mysql -u "$DB_USER" -h 127.0.0.1 "$DB_NAME" -e "$1" 2>/dev/null; }

admin_give() {
  local col="$1" label="$2"
  echo ""
  read -p "$(echo -e "${C}Tên nhân vật: ${N}")" cname
  read -p "$(echo -e "${C}Số $label: ${N}")" amount
  local exist; exist=$(_mysql "SELECT COUNT(*) FROM nro_character WHERE name='$cname';" 2>/dev/null | tail -1)
  if [[ "$exist" == "0" ]]; then
    err "Không tìm thấy '$cname'!"
  else
    _mysql "UPDATE nro_character SET $col=$col+$amount WHERE name='$cname';" && ok "Đã nạp $amount $label cho '$cname'!" || err "Thất bại!"
    _mysql "SELECT name, level, gold, gem FROM nro_character WHERE name='$cname';"
  fi
  read -p $'\e[1;32m[Enter]...\e[0m' _
}

admin_menu() {
  while true; do
    clear
    echo -e "${W}══════ ADMIN TOOL ══════${N}"
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" && echo -e "  ${G}● DB: Online${N}" || echo -e "  ${R}● DB: Offline${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Nạp VÀNG"
    echo -e "  ${Y}[2]${N} Nạp NGỌC"
    echo -e "  ${Y}[3]${N} Nạp EXP"
    echo -e "  ${Y}[4]${N} Danh sách nhân vật"
    echo -e "  ${Y}[5]${N} Tạo tài khoản"
    echo -e "  ${Y}[6]${N} Reset mật khẩu"
    echo -e "  ${Y}[7]${N} Ban / Unban"
    echo -e "  ${Y}[8]${N} SQL tuỳ ý"
    echo -e "  ${Y}[0]${N} Quay lại"
    echo ""
    read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) admin_give "gold" "vàng" ;;
      2) admin_give "gem"  "ngọc" ;;
      3) admin_give "exp"  "EXP"  ;;
      4) echo ""; _mysql "SELECT id, name, level, gold, gem FROM nro_character ORDER BY level DESC LIMIT 30;"; read -p $'\e[1;32m[Enter]...\e[0m' _ ;;
      5)
        read -p "$(echo -e "${C}Username: ${N}")" u
        read -s -p "$(echo -e "${C}Password: ${N}")" p; echo ""
        local h; h=$(echo -n "$p" | md5sum | cut -d' ' -f1)
        _mysql "INSERT INTO account (username, password) VALUES ('$u','$h');" && ok "Tạo '$u' OK!" || err "Thất bại!"
        read -p $'\e[1;32m[Enter]...\e[0m' _
        ;;
      6)
        read -p "$(echo -e "${C}Username: ${N}")" u
        read -s -p "$(echo -e "${C}Pass mới: ${N}")" p; echo ""
        local h; h=$(echo -n "$p" | md5sum | cut -d' ' -f1)
        _mysql "UPDATE account SET password='$h' WHERE username='$u';" && ok "OK!" || err "Thất bại!"
        read -p $'\e[1;32m[Enter]...\e[0m' _
        ;;
      7)
        read -p "$(echo -e "${C}Username: ${N}")" u
        echo -e "  ${Y}[1]${N} Ban  ${Y}[2]${N} Unban"
        read -p "$(echo -e "${C}Chọn: ${N}")" bc
        [[ "$bc" == "1" ]] && _mysql "UPDATE account SET status=0 WHERE username='$u';" && ok "Ban OK" || true
        [[ "$bc" == "2" ]] && _mysql "UPDATE account SET status=1 WHERE username='$u';" && ok "Unban OK" || true
        read -p $'\e[1;32m[Enter]...\e[0m' _
        ;;
      8)
        _mysql "SHOW TABLES;"; echo ""
        read -p "$(echo -e "${C}SQL: ${N}")" sql
        [[ -n "$sql" ]] && _mysql "$sql"
        read -p $'\e[1;32m[Enter]...\e[0m' _
        ;;
      0) break ;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool"
    echo -e "  ${Y}[4]${N} Tải lại APK (patch lại từ Drive)"
    echo -e "  ${Y}[5]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""
    read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _ ;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _ ;;
      3) admin_menu ;;
      4)
        local r; r=$(step_download_apk) && {
          local p; p=$(step_patch_apk "$r") && step_sign_apk "$p"
        } || err "Tải APK thất bại!"
        read -p $'\e[1;32m[Enter]...\e[0m' _
        ;;
      5) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"; read -p $'\e[1;32m[Enter]...\e[0m' _ ;;
      0) echo -e "${G}Bye!${N}"; exit 0 ;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup trước đó — vào menu chính"
  main_menu
  exit 0
fi

# ─── FIRST RUN ────────────────────────────────────────────────────
echo -e "${W}  Auto setup – không cần thao tác thêm${N}"
echo ""

# ── Bước 1 ──
echo -e "${W}━━━ BƯỚC 1/5: Cài packages ━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages
echo ""

# ── Bước 2 ──
echo -e "${W}━━━ BƯỚC 2/5: Khởi động MariaDB ━━━━━━━━━━━━━━━━━${N}"
step_mariadb
echo ""

# ── Bước 3 ──
echo -e "${W}━━━ BƯỚC 3/5: Tải APK từ Google Drive ━━━━━━━━━━━${N}"
APK_RAW=""
APK_RAW=$(step_download_apk) || { err "Bước 3 thất bại! Kiểm tra mạng."; read -p $'[Enter]...' _; exit 1; }
echo ""

# ── Bước 4 ──
echo -e "${W}━━━ BƯỚC 4/5: Patch IP → 127.0.0.1 ━━━━━━━━━━━━━━${N}"
APK_PAT=""
APK_PAT=$(step_patch_apk "$APK_RAW") || { err "Bước 4 thất bại!"; read -p $'[Enter]...' _; exit 1; }
echo ""

# ── Bước 5 ──
echo -e "${W}━━━ BƯỚC 5/5: Ký APK & tạo launcher ━━━━━━━━━━━━━${N}"
step_sign_apk "$APK_PAT"
step_create_launcher

# Đánh dấu xong
mkdir -p "$NRO_HOME"
date > "$SETUP_FLAG"

echo ""
echo -e "${G}╔══════════════════════════════════════════════════╗${N}"
echo -e "${G}║          CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}    $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Local.apk${N}"
echo -e "  2. Copy Srcgame.jar + ServerLogin.jar → ${Y}$NRO_HOME/${N}"
echo -e "  3. Chọn ${Y}[1] Start Server${N} trong menu"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
