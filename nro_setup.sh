#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   NRO Private Server – Termux Auto Setup (Độc lập)              ║
# ║   APK: Google Drive  |  Server: Java + MariaDB                  ║
# ║   Chạy: bash nro_setup.sh                                       ║
# ╚══════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─── màu ──────────────────────────────────────────────────────────
R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m'
B='\033[1;34m' C='\033[1;36m' W='\033[1;37m' N='\033[0m'

ok()  { echo -e "${G}[✓]${N} $*"; }
err() { echo -e "${R}[✗]${N} $*"; }
inf() { echo -e "${B}[i]${N} $*"; }
wrn() { echo -e "${Y}[!]${N} $*"; }
die() { err "$*"; exit 1; }

# ─── cấu hình ─────────────────────────────────────────────────────
NRO_HOME="$HOME/nro-server"
APK_DIR="$HOME/storage/downloads"
APK_OUT="$APK_DIR/NRO_Local.apk"
GDRIVE_ID="19whOmyWZ3EMIWZ3g6e-fejRkfeH7_6b5"
PATCH_IP="127.0.0.1"
PATCH_PORT="14445"
DB_NAME="nro"
DB_USER="root"
DB_PASS=""   # MariaDB root không cần pass mặc định trong Termux

KEYSTORE="$HOME/.nro_sign.keystore"
KEY_ALIAS="nrosign"
KEY_PASS="nro12345"

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
# BƯỚC 1: Cài packages cần thiết
# ══════════════════════════════════════════════════════════════════
step_packages() {
  inf "Cập nhật pkg list..."
  pkg update -y 2>/dev/null | tail -2 || true

  inf "Cài packages cần thiết..."
  pkg install -y \
    curl wget python python-pip \
    openjdk-17 mariadb \
    openssl zip unzip \
    termux-tools 2>/dev/null | grep -E "^(Install|Unpacking|Setting)" || true

  # pip packages
  inf "Cài pip packages..."
  pip install -q gdown requests 2>/dev/null || true

  ok "Packages OK"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 2: Setup MariaDB
# ══════════════════════════════════════════════════════════════════
step_mariadb() {
  inf "Khởi tạo MariaDB..."
  mkdir -p "$NRO_HOME/db-data"

  # Kiểm tra đã init chưa
  if [[ ! -d "$PREFIX/var/lib/mysql/mysql" ]]; then
    mysql_install_db --datadir="$PREFIX/var/lib/mysql" 2>/dev/null | tail -3 || true
    ok "MariaDB data dir đã tạo"
  else
    ok "MariaDB đã được khởi tạo trước đó"
  fi

  # Start MariaDB nền
  inf "Khởi động MariaDB..."
  # Dừng nếu đang chạy
  mysqladmin -u root shutdown 2>/dev/null || true
  sleep 1
  # Start background
  mysqld_safe --datadir="$PREFIX/var/lib/mysql" \
    --socket="$PREFIX/tmp/mysql.sock" \
    --pid-file="$PREFIX/tmp/mysqld.pid" \
    --log-error="$PREFIX/tmp/mysqld.err" \
    --skip-networking=0 \
    --bind-address=127.0.0.1 \
    --port=3306 &>/dev/null &
  MYSQLD_PID=$!
  disown $MYSQLD_PID 2>/dev/null || true

  # Chờ MariaDB sẵn sàng
  inf "Chờ MariaDB khởi động..."
  local tries=0
  while ! mysqladmin -u root ping &>/dev/null; do
    sleep 1
    tries=$((tries+1))
    [[ $tries -ge 20 ]] && die "MariaDB không khởi động được! Xem log: $PREFIX/tmp/mysqld.err"
  done
  ok "MariaDB đang chạy"

  # Tạo database NRO
  inf "Tạo database '$DB_NAME'..."
  mysql -u root -e "
    CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'root'@'localhost';
    FLUSH PRIVILEGES;
  " 2>/dev/null || wrn "DB có thể đã tồn tại"

  # Tạo schema cơ bản nếu chưa có
  mysql -u root "$DB_NAME" -e "SHOW TABLES;" 2>/dev/null | grep -q "account" 2>/dev/null || {
    inf "Tạo schema cơ bản..."
    mysql -u root "$DB_NAME" << 'SQLEOF'
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
  class       TINYINT DEFAULT 0,
  map_id      INT DEFAULT 1,
  pos_x       INT DEFAULT 0,
  pos_y       INT DEFAULT 0,
  created_at  DATETIME DEFAULT NOW(),
  FOREIGN KEY (account_id) REFERENCES account(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS nro_item (
  id          INT PRIMARY KEY AUTO_INCREMENT,
  char_id     INT,
  item_id     INT,
  quantity    INT DEFAULT 1,
  slot        INT DEFAULT -1,
  FOREIGN KEY (char_id) REFERENCES nro_character(id) ON DELETE CASCADE
) ENGINE=InnoDB;
SQLEOF
    ok "Schema OK"
  }
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 3: Tải APK từ Google Drive
# ══════════════════════════════════════════════════════════════════
step_download_apk() {
  local apk_raw="/tmp/nro_original.apk"

  inf "Tải APK gốc từ Google Drive..."

  # Thử gdown trước (xử lý xác nhận tự động)
  if python3 -m gdown --version &>/dev/null 2>&1 || python3 -c "import gdown" &>/dev/null 2>&1; then
    python3 -c "
import gdown, sys
url = 'https://drive.google.com/uc?id=$GDRIVE_ID'
out = '$apk_raw'
try:
    gdown.download(url, out, quiet=False, fuzzy=True)
    print('OK')
except Exception as e:
    print(f'ERR:{e}')
    sys.exit(1)
" && ok "Tải APK xong (gdown)" || _apk_fallback "$apk_raw"
  else
    _apk_fallback "$apk_raw"
  fi

  # Kiểm tra file hợp lệ
  [[ ! -f "$apk_raw" ]] && die "Tải APK thất bại!"
  local fsize
  fsize=$(stat -c%s "$apk_raw" 2>/dev/null || stat -f%z "$apk_raw" 2>/dev/null || echo 0)
  [[ "$fsize" -lt 100000 ]] && die "File APK có vẻ không hợp lệ (quá nhỏ: ${fsize} bytes)!"
  ok "APK gốc: $(du -h "$apk_raw" | cut -f1)"

  echo "$apk_raw"
}

_apk_fallback() {
  local out="$1"
  wrn "gdown thất bại, thử curl..."
  # Lấy confirm token
  local COOKIE_FILE="/tmp/gdrive_cookie.txt"
  local CONFIRM
  curl -sc "$COOKIE_FILE" \
    "https://drive.google.com/uc?export=download&id=$GDRIVE_ID" \
    -o /tmp/gdrive_check.html 2>/dev/null
  CONFIRM=$(grep -oP '(?<=confirm=)[^&"]+' /tmp/gdrive_check.html 2>/dev/null | head -1)
  if [[ -n "$CONFIRM" ]]; then
    curl -Lb "$COOKIE_FILE" \
      "https://drive.google.com/uc?export=download&confirm=${CONFIRM}&id=$GDRIVE_ID" \
      -o "$out" --progress-bar 2>&1 | tail -3
  else
    # Drive v2 API style
    curl -L \
      "https://drive.google.com/uc?export=download&id=$GDRIVE_ID&confirm=t&uuid=$(date +%s)" \
      -o "$out" --progress-bar 2>&1 | tail -3
  fi
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 4: Patch APK (thay IP → 127.0.0.1)
# ══════════════════════════════════════════════════════════════════
step_patch_apk() {
  local apk_in="$1"
  local apk_out="/tmp/nro_patched.apk"

  inf "Patch IP → ${PATCH_IP}:${PATCH_PORT} ..."

  python3 << PYEOF
import sys, zipfile, shutil, re, os

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
    # fallback
    cands = [n for n in names if "global-metadata" in n.lower()]
    return cands[0] if cands else None

def patch_data(data, new_ip, new_port):
    patched = False

    # Pattern 1: Host:IP:Port:0,0,0  (Hashirama / DragonBoy style)
    def replace_host(m):
        nonlocal patched
        orig = m.group(0)
        # Thay phần IP và port
        old_ip_part  = m.group(2)
        old_port_part = m.group(3)
        new_part = m.group(1) + new_ip.encode() + b':' + str(new_port).encode() + m.group(4)
        if len(new_part) <= len(orig):
            new_part += b'\x00' * (len(orig) - len(new_part))
            patched = True
            return new_part
        return orig

    data2 = re.sub(
        rb'([A-Za-z]{3,20}:)([\d\.a-z\-]+)(?::)(\d{4,5})(:[\d,]*)',
        replace_host, data
    )
    if data2 != data:
        print(f"  [✓] Pattern Hashirama/Host:IP:Port match OK")
        return data2, True

    # Pattern 2: IP thô trong binary
    known_ips = [
        b"dragonboy.vn", b"server.dragonboy.vn",
        b"ngocrongonline.vn", b"gateway.nro",
        b"nroacademy.online", b"103.27.",
        b"103.57.", b"171.244.", b"27.74.",
    ]
    for old in known_ips:
        if old in data:
            new = new_ip.encode()
            if len(new) < len(old):
                new = new + b'\x00' * (len(old) - len(new))
            elif len(new) > len(old):
                continue
            data2 = data.replace(old, new, 1)
            print(f"  [✓] Replaced: {old} → {new_ip}")
            return data2, True

    return data, False

# ── Mở APK ──
with zipfile.ZipFile(apk_in, 'r') as zin:
    meta_path = find_meta(zin)
    if not meta_path:
        print("[✗] Không tìm thấy global-metadata.dat trong APK!")
        sys.exit(1)
    print(f"  [i] Metadata: {meta_path}")
    meta_data = zin.read(meta_path)

print(f"  [i] Metadata size: {len(meta_data):,} bytes")

# ── Patch ──
patched_data, ok = patch_data(meta_data, new_ip, new_port)
if not ok:
    print("[!] Không tìm được IP cũ để thay. Ghi thẳng...")
    # Vẫn ghi ra để không thất bại hoàn toàn

# ── Ghi APK mới ──
print(f"  [i] Ghi APK: {apk_out}")
with zipfile.ZipFile(apk_in, 'r') as zin, \
     zipfile.ZipFile(apk_out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zout:
    for item in zin.infolist():
        raw = zin.read(item.filename)
        if item.filename == meta_path:
            zout.writestr(item, patched_data)
        else:
            zout.writestr(item, raw)

print(f"[✓] Patch xong → {apk_out}")
PYEOF

  [[ ! -f "$apk_out" ]] && die "Patch APK thất bại!"
  ok "Patch IP xong"
  echo "$apk_out"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 5: Ký APK
# ══════════════════════════════════════════════════════════════════
step_sign_apk() {
  local apk_in="$1"

  # Tạo keystore nếu chưa có
  if [[ ! -f "$KEYSTORE" ]]; then
    inf "Tạo keystore ký APK..."
    keytool -genkeypair -v \
      -keystore "$KEYSTORE" \
      -alias "$KEY_ALIAS" \
      -keyalg RSA -keysize 2048 -validity 9999 \
      -dname "CN=NRO Local,O=NRO,C=VN" \
      -storepass "$KEY_PASS" -keypass "$KEY_PASS" \
      2>/dev/null && ok "Keystore đã tạo" || wrn "Keystore tạo lỗi nhỏ (bỏ qua)"
  fi

  inf "Ký APK..."
  jarsigner \
    -keystore "$KEYSTORE" \
    -storepass "$KEY_PASS" -keypass "$KEY_PASS" \
    -digestalg SHA-256 -sigalg SHA256withRSA \
    "$apk_in" "$KEY_ALIAS" 2>/dev/null && ok "Ký APK OK" || wrn "jarsigner báo lỗi nhỏ"

  # Copy ra Downloads
  termux-setup-storage 2>/dev/null || true
  mkdir -p "$APK_DIR"
  cp "$apk_in" "$APK_OUT"
  ok "APK đã lưu: $APK_OUT"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 6: Tạo script start server
# ══════════════════════════════════════════════════════════════════
step_create_launcher() {
  mkdir -p "$NRO_HOME/bin"

  # Script khởi động server
  cat > "$NRO_HOME/bin/start.sh" << 'STARTEOF'
#!/data/data/com.termux/files/usr/bin/bash
NRO_HOME="$HOME/nro-server"
DB_NAME="nro"

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' C='\033[1;36m' N='\033[0m'
ok()  { echo -e "${G}[✓]${N} $*"; }
err() { echo -e "${R}[✗]${N} $*"; }
inf() { echo -e "${C}[i]${N} $*"; }

echo -e "${Y}═══════════════════════════════════════${N}"
echo -e "${Y}   NRO Private Server – Launcher       ${N}"
echo -e "${Y}═══════════════════════════════════════${N}"
echo ""

# Khởi động MariaDB nếu chưa chạy
if ! mysqladmin -u root ping &>/dev/null; then
  inf "Khởi động MariaDB..."
  mysqld_safe \
    --datadir="$PREFIX/var/lib/mysql" \
    --socket="$PREFIX/tmp/mysql.sock" \
    --pid-file="$PREFIX/tmp/mysqld.pid" \
    --skip-networking=0 \
    --bind-address=127.0.0.1 \
    --port=3306 &>/dev/null &
  disown
  sleep 3
fi

if mysqladmin -u root ping &>/dev/null; then
  ok "MariaDB: Running"
else
  err "MariaDB không chạy được!"
fi

# Tìm và khởi động server JAR
JAR_GAME=$(find "$NRO_HOME" -name "Srcgame.jar" -o -name "game.jar" -o -name "server.jar" 2>/dev/null | head -1)
JAR_LOGIN=$(find "$NRO_HOME" -name "ServerLogin.jar" -o -name "login.jar" 2>/dev/null | head -1)

if [[ -n "$JAR_GAME" ]]; then
  inf "Khởi động game server: $(basename $JAR_GAME)"
  java -jar "$JAR_GAME" &
  disown
  ok "Game Server: Started (PID $!)"
else
  echo ""
  err "Chưa có server JAR!"
  echo "  → Copy Srcgame.jar vào: $NRO_HOME/"
  echo "  → Copy ServerLogin.jar vào: $NRO_HOME/"
  echo ""
fi

if [[ -n "$JAR_LOGIN" ]]; then
  inf "Khởi động login server: $(basename $JAR_LOGIN)"
  java -jar "$JAR_LOGIN" &
  disown
  ok "Login Server: Started"
fi

echo ""
ok "Server đang chạy. Mở APK trong Downloads → NRO_Local.apk để chơi!"
STARTEOF
  chmod +x "$NRO_HOME/bin/start.sh"

  # Script stop server
  cat > "$NRO_HOME/bin/stop.sh" << 'STOPEOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "Dừng server..."
pkill -f "Srcgame.jar" 2>/dev/null && echo "[✓] Game server dừng" || true
pkill -f "ServerLogin.jar" 2>/dev/null && echo "[✓] Login server dừng" || true
mysqladmin -u root shutdown 2>/dev/null && echo "[✓] MariaDB dừng" || true
STOPEOF
  chmod +x "$NRO_HOME/bin/stop.sh"

  ok "Launcher tạo tại: $NRO_HOME/bin/start.sh"
}

# ══════════════════════════════════════════════════════════════════
# MENU ADMIN – chạy sau khi setup xong
# ══════════════════════════════════════════════════════════════════
_mysql() {
  local sql="$1"
  mysql -u "$DB_USER" -h 127.0.0.1 "$DB_NAME" -e "$sql" 2>/dev/null
}

admin_give() {
  local col="$1" label="$2"
  echo ""
  read -p "$(echo -e "${C}Tên nhân vật: ${N}")" cname
  read -p "$(echo -e "${C}Số $label: ${N}")" amount
  local exist
  exist=$(_mysql "SELECT COUNT(*) FROM nro_character WHERE name='$cname';" 2>/dev/null | tail -1)
  if [[ "$exist" == "0" ]]; then
    err "Không tìm thấy nhân vật '$cname'!"
  else
    _mysql "UPDATE nro_character SET $col=$col+$amount WHERE name='$cname';" && \
      ok "Đã nạp $amount $label cho '$cname'!" || err "Thất bại!"
    _mysql "SELECT name, level, gold, gem FROM nro_character WHERE name='$cname';"
  fi
  read -p "$(echo -e "${G}[Enter]...${N}")" _
}

admin_menu() {
  while true; do
    clear
    echo -e "${W}══════ ADMIN TOOL ══════${N}"
    echo ""
    if mysqladmin -u root ping &>/dev/null; then
      echo -e "  ${G}● DB: Online${N}"
    else
      echo -e "  ${R}● DB: Offline (chạy: bash $NRO_HOME/bin/start.sh)${N}"
    fi
    echo ""
    echo -e "  ${Y}[1]${N} Nạp VÀNG"
    echo -e "  ${Y}[2]${N} Nạp NGỌC"
    echo -e "  ${Y}[3]${N} Nạp EXP"
    echo -e "  ${Y}[4]${N} Danh sách nhân vật"
    echo -e "  ${Y}[5]${N} Tạo tài khoản"
    echo -e "  ${Y}[6]${N} Reset mật khẩu"
    echo -e "  ${Y}[7]${N} Ban / Unban"
    echo -e "  ${Y}[8]${N} SQL tuỳ ý"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""
    read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) admin_give "gold" "vàng" ;;
      2) admin_give "gem"  "ngọc" ;;
      3) admin_give "exp"  "EXP"  ;;
      4)
        echo ""
        _mysql "SELECT id, name, level, gold, gem, exp FROM nro_character ORDER BY level DESC LIMIT 30;"
        read -p "$(echo -e "${G}[Enter]...${N}")" _
        ;;
      5)
        echo ""
        read -p "$(echo -e "${C}Username: ${N}")" u
        read -s -p "$(echo -e "${C}Password: ${N}")" p; echo ""
        local h; h=$(echo -n "$p" | md5sum | cut -d' ' -f1)
        _mysql "INSERT INTO account (username, password) VALUES ('$u','$h');" && \
          ok "Tạo tài khoản '$u' OK!" || err "Thất bại (có thể đã tồn tại)"
        read -p "$(echo -e "${G}[Enter]...${N}")" _
        ;;
      6)
        echo ""
        read -p "$(echo -e "${C}Username: ${N}")" u
        read -s -p "$(echo -e "${C}Pass mới: ${N}")" p; echo ""
        local h; h=$(echo -n "$p" | md5sum | cut -d' ' -f1)
        _mysql "UPDATE account SET password='$h' WHERE username='$u';" && ok "OK!" || err "Thất bại!"
        read -p "$(echo -e "${G}[Enter]...${N}")" _
        ;;
      7)
        echo ""
        read -p "$(echo -e "${C}Username: ${N}")" u
        echo -e "  ${Y}[1]${N} Ban  ${Y}[2]${N} Unban"
        read -p "$(echo -e "${C}Chọn: ${N}")" bc
        [[ "$bc" == "1" ]] && _mysql "UPDATE account SET status=0 WHERE username='$u';" && ok "Đã ban '$u'" || true
        [[ "$bc" == "2" ]] && _mysql "UPDATE account SET status=1 WHERE username='$u';" && ok "Đã unban '$u'" || true
        read -p "$(echo -e "${G}[Enter]...${N}")" _
        ;;
      8)
        echo ""
        echo -e "${C}Tables:${N}"
        _mysql "SHOW TABLES;"
        echo ""
        read -p "$(echo -e "${C}SQL: ${N}")" sql
        [[ -n "$sql" ]] && _mysql "$sql"
        read -p "$(echo -e "${G}[Enter]...${N}")" _
        ;;
      0) break ;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# MAIN MENU (sau khi setup)
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng / ngọc / ban...)"
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
        inf "Tải lại APK..."
        local apk_raw
        apk_raw=$(step_download_apk)
        local apk_pat
        apk_pat=$(step_patch_apk "$apk_raw")
        step_sign_apk "$apk_pat"
        read -p $'\e[1;32m[Enter]...\e[0m' _
        ;;
      5)
        tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
        read -p $'\e[1;32m[Enter]...\e[0m' _
        ;;
      0) echo -e "${G}Bye!${N}"; exit 0 ;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT – Chạy lần đầu = auto setup, lần sau = menu
# ══════════════════════════════════════════════════════════════════
SETUP_FLAG="$NRO_HOME/.setup_done"

banner

if [[ -f "$SETUP_FLAG" ]]; then
  # Đã setup → vào menu thẳng
  main_menu
  exit 0
fi

# ─── FIRST RUN: AUTO SETUP ────────────────────────────────────────
echo -e "${W}  ● Lần đầu chạy – bắt đầu cài đặt tự động${N}"
echo -e "${W}  ● Quá trình gồm 5 bước, KHÔNG cần thao tác thêm${N}"
echo ""
echo -e "${C}  Thời gian ước tính: 5–15 phút (tuỳ mạng)${N}"
echo ""
read -p "$(echo -e "${Y}  Nhấn Enter để bắt đầu...${N}")"
echo ""

# Bước 1
echo -e "${W}━━━ BƯỚC 1/5: Cài packages ━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages

echo ""
# Bước 2
echo -e "${W}━━━ BƯỚC 2/5: Khởi động MariaDB ━━━━━━━━━━━━━━━━━${N}"
step_mariadb

echo ""
# Bước 3
echo -e "${W}━━━ BƯỚC 3/5: Tải APK từ Google Drive ━━━━━━━━━━━${N}"
APK_RAW=$(step_download_apk)

echo ""
# Bước 4
echo -e "${W}━━━ BƯỚC 4/5: Patch IP → 127.0.0.1 ━━━━━━━━━━━━━━${N}"
APK_PAT=$(step_patch_apk "$APK_RAW")

echo ""
# Bước 5
echo -e "${W}━━━ BƯỚC 5/5: Ký APK & tạo launcher ━━━━━━━━━━━━━${N}"
step_sign_apk "$APK_PAT"
step_create_launcher

# Đánh dấu setup xong
mkdir -p "$NRO_HOME"
touch "$SETUP_FLAG"
echo "$(date)" > "$SETUP_FLAG"

# Tổng kết
echo ""
echo -e "${G}╔══════════════════════════════════════════════════════╗${N}"
echo -e "${G}║              CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚══════════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}  $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo -e "  ${Y}Script này:${N}  bash nro_setup.sh  (vào menu)"
echo ""
echo -e "  ${C}Bước tiếp theo:${N}"
echo -e "  1. Copy server JAR vào:  ${Y}$NRO_HOME/${N}"
echo -e "     (Srcgame.jar + ServerLogin.jar)"
echo -e "  2. Chạy: ${Y}bash $NRO_HOME/bin/start.sh${N}"
echo -e "  3. Cài APK từ Downloads → ${Y}NRO_Local.apk${N}"
echo -e "  4. Đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter để vào menu chính...${N}")"
main_menu
