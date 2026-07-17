#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   NRO / Hashirama – Termux Auto Setup                          ║
# ║   Nguồn: Google Drive RAR (APK + JARs + SQL đầy đủ)           ║
# ║   Chạy: bash nro_setup.sh                                      ║
# ╚══════════════════════════════════════════════════════════════════╝

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m'
B='\033[1;34m' C='\033[1;36m' W='\033[1;37m' N='\033[0m'
ok()  { echo -e "${G}[✓]${N} $*"; }
err() { echo -e "${R}[✗]${N} $*"; }
inf() { echo -e "${B}[i]${N} $*"; }
wrn() { echo -e "${Y}[!]${N} $*"; }

# ─── Config ───────────────────────────────────────────────────────
NRO_HOME="$HOME/nro-server"
APK_OUT="$HOME/storage/downloads/NRO_Hashirama.apk"
GDRIVE_ID="19whOmyWZ3EMIWZ3g6e-fejRkfeH7_6b5"
DB_NAME="hashirama"
RAR_TMP="/tmp/nro_drive.rar"
SETUP_FLAG="$NRO_HOME/.setup_done"

KEYSTORE="$HOME/.nro_sign.keystore"
KEY_ALIAS="nrosign"
KEY_PASS="nro12345"

# File cần lấy trong RAR
RAR_APK="SRC5M/ClientGame/Hashirama-Androi.apk"
RAR_JAR_GAME="SRC5M/LOCAL.jar/Srcgame.jar"
RAR_JAR_LOGIN="SRC5M/ServerLogin/ServerLogin.jar"
RAR_SQL="SRC5M/Hashirama/Sql/nrofree2025_11thang3.sql"

banner() {
  clear
  echo -e "${C}"
  echo "  ██╗  ██╗ █████╗ ███████╗██╗  ██╗██╗██████╗  █████╗ "
  echo "  ██║  ██║██╔══██╗██╔════╝██║  ██║██║██╔══██╗██╔══██╗"
  echo "  ███████║███████║███████╗███████║██║██████╔╝███████║"
  echo "  ██╔══██║██╔══██║╚════██║██╔══██║██║██╔══██╗██╔══██║"
  echo "  ██║  ██║██║  ██║███████║██║  ██║██║██║  ██║██║  ██║"
  echo "  ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝  ╚═╝"
  echo -e "${Y}         NRO Private Server – Termux Setup${N}"
  echo -e "${G}  ══════════════════════════════════════════════${N}"
  echo ""
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 1 – Packages
# ══════════════════════════════════════════════════════════════════
step_packages() {
  inf "Cập nhật pkg..."
  pkg update -y 2>/dev/null | tail -1 || true

  inf "Cài packages..."
  pkg install -y curl wget openjdk-17 mariadb unrar openssl 2>&1 \
    | grep "^Setting up" || true

  ok "Packages xong!"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 2 – Tải RAR từ Google Drive (resume nếu bị ngắt)
# ══════════════════════════════════════════════════════════════════
step_download_rar() {
  local DRIVE_URL="https://drive.usercontent.google.com/download?id=${GDRIVE_ID}&export=download&authuser=0&confirm=t"

  # Kiểm tra file đã tải xong chưa
  if [[ -f "$RAR_TMP" ]]; then
    local sz; sz=$(stat -c%s "$RAR_TMP" 2>/dev/null || echo 0)
    if [[ "$sz" -gt 2000000000 ]]; then
      ok "RAR đã có sẵn ($(du -h "$RAR_TMP" | cut -f1)) – bỏ qua tải"
      return 0
    fi
    wrn "RAR chưa đầy đủ (${sz} bytes) – tiếp tục tải..."
  fi

  inf "Tải RAR từ Google Drive (~2.2GB)..."
  wrn "Cần dung lượng trống ~5GB và mạng ổn định"
  echo ""

  curl -L -A "Mozilla/5.0" \
    --retry 5 --retry-delay 10 \
    --continue-at - \
    --progress-bar \
    "$DRIVE_URL" \
    -o "$RAR_TMP"

  local sz; sz=$(stat -c%s "$RAR_TMP" 2>/dev/null || echo 0)
  if [[ "$sz" -lt 1000000000 ]]; then
    # Thử wget với resume
    wrn "curl chưa đủ ($sz bytes), thử wget..."
    wget -c --show-progress -q "$DRIVE_URL" -O "$RAR_TMP" || true
    sz=$(stat -c%s "$RAR_TMP" 2>/dev/null || echo 0)
  fi

  if [[ "$sz" -lt 1000000000 ]]; then
    err "Tải thất bại! Kích thước: $sz bytes"
    return 1
  fi

  ok "Tải xong: $(du -h "$RAR_TMP" | cut -f1)"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 3 – Giải nén đúng 4 file cần thiết từ RAR
# ══════════════════════════════════════════════════════════════════
step_extract() {
  mkdir -p "$NRO_HOME/bin" "$NRO_HOME/sql"

  # ── Giải nén bằng unrar (chỉ lấy file cụ thể) ──
  inf "Giải nén APK game..."
  unrar e -y "$RAR_TMP" "$RAR_APK" /tmp/ 2>/dev/null \
    && ok "APK OK: $(ls -lh /tmp/Hashirama-Androi.apk 2>/dev/null | awk '{print $5}')" \
    || { err "unrar APK thất bại! Thử p7zip..."; _extract_7z_apk; }

  inf "Giải nén Srcgame.jar..."
  unrar e -y "$RAR_TMP" "$RAR_JAR_GAME" "$NRO_HOME/bin/" 2>/dev/null \
    && ok "Srcgame.jar OK" \
    || wrn "Srcgame.jar thất bại (bỏ qua)"

  inf "Giải nén ServerLogin.jar..."
  unrar e -y "$RAR_TMP" "$RAR_JAR_LOGIN" "$NRO_HOME/bin/" 2>/dev/null \
    && ok "ServerLogin.jar OK" \
    || wrn "ServerLogin.jar thất bại (bỏ qua)"

  inf "Giải nén SQL..."
  unrar e -y "$RAR_TMP" "$RAR_SQL" "$NRO_HOME/sql/" 2>/dev/null \
    && ok "SQL OK" \
    || wrn "SQL thất bại (bỏ qua)"
}

_extract_7z_apk() {
  # Fallback: dùng Python parser tự viết để extract APK
  pkg install -y p7zip 2>/dev/null | grep "Setting up" || true
  7z e -y "$RAR_TMP" "$RAR_APK" -o/tmp/ 2>/dev/null \
    && ok "APK OK (7z)" \
    || err "Không giải nén được APK!"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 4 – Ký APK
# ══════════════════════════════════════════════════════════════════
step_sign_apk() {
  local apk_src="/tmp/Hashirama-Androi.apk"

  if [[ ! -f "$apk_src" ]]; then
    err "Không tìm thấy APK để ký!"
    return 1
  fi

  # Tạo keystore nếu chưa có
  if [[ ! -f "$KEYSTORE" ]]; then
    inf "Tạo keystore..."
    keytool -genkeypair -v \
      -keystore "$KEYSTORE" \
      -alias "$KEY_ALIAS" \
      -keyalg RSA -keysize 2048 -validity 9999 \
      -dname "CN=NRO,O=NRO,C=VN" \
      -storepass "$KEY_PASS" -keypass "$KEY_PASS" 2>/dev/null \
      && ok "Keystore OK" || wrn "Keystore tạo có cảnh báo"
  fi

  inf "Ký APK..."
  jarsigner \
    -keystore "$KEYSTORE" \
    -storepass "$KEY_PASS" -keypass "$KEY_PASS" \
    -digestalg SHA-256 -sigalg SHA256withRSA \
    "$apk_src" "$KEY_ALIAS" 2>/dev/null \
    && ok "Ký OK" || wrn "jarsigner có cảnh báo nhỏ"

  termux-setup-storage 2>/dev/null || true
  mkdir -p "$(dirname "$APK_OUT")"
  cp "$apk_src" "$APK_OUT"
  ok "APK lưu → $APK_OUT"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 5 – Setup MariaDB + import SQL
# ══════════════════════════════════════════════════════════════════
step_mariadb() {
  # Init nếu chưa có
  if [[ ! -d "$PREFIX/var/lib/mysql/mysql" ]]; then
    inf "Init MariaDB..."
    mysql_install_db 2>&1 | tail -3 || true
  else
    ok "MariaDB đã init"
  fi

  # Dừng instance cũ
  pkill mysqld 2>/dev/null || true
  sleep 2

  # Start
  inf "Khởi động MariaDB..."
  mysqld_safe --user="$(whoami)" 2>/dev/null &
  disown

  # Chờ tối đa 30s
  local i=0
  while [[ $i -lt 30 ]]; do
    sleep 1; i=$((i+1))
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" && break
    echo -ne "  Chờ... ${i}s\r"
  done
  echo ""

  if ! mysqladmin -u root ping 2>/dev/null | grep -q "alive"; then
    wrn "MariaDB chưa phản hồi – tiếp tục..."
    return 0
  fi
  ok "MariaDB đang chạy!"

  # Tạo DB hashirama
  inf "Tạo database '$DB_NAME'..."
  mysql -u root 2>/dev/null << SQLEOF || true
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'root'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'root'@'127.0.0.1';
FLUSH PRIVILEGES;
SQLEOF

  # Import SQL nếu có
  local sql_file
  sql_file=$(find "$NRO_HOME/sql" -name "*.sql" -size +100k 2>/dev/null | sort -t_ -k1 | tail -1)
  if [[ -n "$sql_file" ]]; then
    inf "Import SQL: $(basename $sql_file)..."
    mysql -u root "$DB_NAME" < "$sql_file" 2>/dev/null \
      && ok "Import SQL xong!" \
      || wrn "Import SQL có lỗi (có thể đã import trước đó)"
  else
    wrn "Không tìm thấy SQL file"
  fi

  ok "Database '$DB_NAME' sẵn sàng"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 6 – Tạo script start/stop
# ══════════════════════════════════════════════════════════════════
step_create_launcher() {
  cat > "$NRO_HOME/bin/start.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
NRO_HOME="$HOME/nro-server"
G='\033[1;32m' R='\033[1;31m' C='\033[1;36m' Y='\033[1;33m' N='\033[0m'
ok()  { echo -e "${G}[✓]${N} $*"; }
err() { echo -e "${R}[✗]${N} $*"; }
inf() { echo -e "${C}[i]${N} $*"; }

echo -e "${Y}══════ Hashirama NRO Launcher ══════${N}"

# Start MariaDB
if ! mysqladmin -u root ping 2>/dev/null | grep -q "alive"; then
  inf "Khởi động MariaDB..."
  mysqld_safe --user="$(whoami)" 2>/dev/null &
  disown; sleep 4
fi
mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
  && ok "MariaDB: Running" || err "MariaDB: Lỗi"

# Start ServerLogin
JAR_LOGIN="$NRO_HOME/bin/ServerLogin.jar"
if [[ -f "$JAR_LOGIN" ]]; then
  inf "Start ServerLogin..."
  cd "$NRO_HOME/bin"
  java -jar ServerLogin.jar &
  disown; ok "ServerLogin: PID $!"
else
  err "Thiếu ServerLogin.jar!"
fi

sleep 2

# Start Srcgame (game server)
JAR_GAME="$NRO_HOME/bin/Srcgame.jar"
if [[ -f "$JAR_GAME" ]]; then
  inf "Start Srcgame..."
  cd "$NRO_HOME/bin"
  java -jar Srcgame.jar &
  disown; ok "Srcgame: PID $!"
else
  err "Thiếu Srcgame.jar!"
fi

echo ""
ok "Server đang chạy!"
ok "APK: Downloads/NRO_Hashirama.apk — cài lên máy và chơi!"
EOF
  chmod +x "$NRO_HOME/bin/start.sh"

  cat > "$NRO_HOME/bin/stop.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f Srcgame.jar      2>/dev/null && echo "[✓] Srcgame dừng"      || true
pkill -f ServerLogin.jar  2>/dev/null && echo "[✓] ServerLogin dừng"  || true
mysqladmin -u root shutdown 2>/dev/null && echo "[✓] MariaDB dừng"    || true
EOF
  chmod +x "$NRO_HOME/bin/stop.sh"
  ok "Launcher: $NRO_HOME/bin/start.sh"
}

# ══════════════════════════════════════════════════════════════════
# ADMIN MENU
# ══════════════════════════════════════════════════════════════════
_mysql() { mysql -u root -h 127.0.0.1 "$DB_NAME" -e "$1" 2>/dev/null; }

# ── Helper tìm tên cột thực tế trong DB ──────────────────────────
_find_col() {
  local tbl="$1"; shift
  for col in "$@"; do
    _mysql "SHOW COLUMNS FROM $tbl LIKE '$col';" 2>/dev/null | grep -q "$col" && echo "$col" && return
  done
  echo "$1"  # default = tên đầu tiên
}

_char_tbl()  { _mysql "SHOW TABLES;" 2>/dev/null | grep -Ei "nhan_vat|character|nro_char|player" | head -1; }
_acc_tbl()   { _mysql "SHOW TABLES;" 2>/dev/null | grep -Ei "account|user|member" | head -1; }

_get_char() {
  echo ""; read -p "$(echo -e "${C}Tên nhân vật: ${N}")" _CN
  echo "$_CN"
}

# ── Nạp stat ─────────────────────────────────────────────────────
admin_give() {
  local col_candidates=("$@")
  local label="${col_candidates[-1]}"
  unset 'col_candidates[-1]'

  local CTBL; CTBL=$(_char_tbl)
  [[ -z "$CTBL" ]] && { err "Không tìm thấy bảng nhân vật!"; sleep 2; return; }
  local COL; COL=$(_find_col "$CTBL" "${col_candidates[@]}")

  echo ""; read -p "$(echo -e "${C}Tên nhân vật: ${N}")" cn
  read -p "$(echo -e "${C}Số $label cần nạp: ${N}")" amt
  local ex; ex=$(_mysql "SELECT COUNT(*) FROM $CTBL WHERE name='$cn';" 2>/dev/null | tail -1)
  if [[ "$ex" == "0" ]]; then
    err "Không tìm thấy '$cn'!"
  else
    _mysql "UPDATE $CTBL SET $COL=$COL+$amt WHERE name='$cn';" \
      && ok "✓ Nạp $amt $label cho '$cn'" || err "Thất bại!"
    _mysql "SELECT name,level,$COL FROM $CTBL WHERE name='$cn';" 2>/dev/null
  fi
  read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _
}

# ── Set level ────────────────────────────────────────────────────
admin_set_level() {
  local CTBL; CTBL=$(_char_tbl)
  echo ""; read -p "$(echo -e "${C}Tên nhân vật: ${N}")" cn
  read -p "$(echo -e "${C}Level muốn set: ${N}")" lv
  read -p "$(echo -e "${C}EXP thêm (Enter=0): ${N}")" ex; ex="${ex:-0}"
  local ECOL; ECOL=$(_find_col "$CTBL" exp kinh_nghiem experience)
  _mysql "UPDATE $CTBL SET level=$lv, $ECOL=$ECOL+$ex WHERE name='$cn';" \
    && ok "Set level $lv + $ex EXP cho '$cn'" || err "Thất bại!"
  _mysql "SELECT name,level,$ECOL FROM $CTBL WHERE name='$cn';" 2>/dev/null
  read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _
}

# ── Cho item / trang bị ──────────────────────────────────────────
admin_give_item() {
  local CTBL; CTBL=$(_char_tbl)
  local ITBL; ITBL=$(_mysql "SHOW TABLES;" 2>/dev/null | grep -Ei "item|do|trang_bi" | head -1)
  echo ""
  if [[ -z "$ITBL" ]]; then
    wrn "Không tìm thấy bảng item trong DB"
    inf "Thử dùng SQL tuỳ ý để xem cấu trúc"
    read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _; return
  fi
  echo -e "${C}Bảng item: $ITBL${N}"
  _mysql "DESCRIBE $ITBL;" 2>/dev/null
  echo ""
  read -p "$(echo -e "${C}Tên nhân vật: ${N}")" cn
  read -p "$(echo -e "${C}Item ID: ${N}")" iid
  read -p "$(echo -e "${C}Số lượng [1]: ${N}")" qty; qty="${qty:-1}"
  local cid; cid=$(_mysql "SELECT id FROM $CTBL WHERE name='$cn';" 2>/dev/null | tail -1)
  if [[ -z "$cid" || "$cid" == "id" ]]; then
    err "Không tìm thấy nhân vật '$cn'!"
  else
    _mysql "INSERT INTO $ITBL (char_id, item_id, quantity) VALUES ($cid,$iid,$qty);" 2>/dev/null \
      || _mysql "INSERT INTO $ITBL (nhan_vat_id, item_id, so_luong) VALUES ($cid,$iid,$qty);" 2>/dev/null \
      && ok "Cho item $iid x$qty vào túi '$cn'" || err "Thất bại — thử SQL tuỳ ý"
  fi
  read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _
}

# ── Xem top bảng xếp hạng ────────────────────────────────────────
admin_top() {
  local CTBL; CTBL=$(_char_tbl)
  echo ""
  echo -e "${Y}══ TOP 20 NHÂN VẬT ══${N}"
  _mysql "SELECT name, level, vang, ngoc FROM $CTBL ORDER BY level DESC, vang DESC LIMIT 20;" 2>/dev/null \
    || _mysql "SELECT name, level FROM $CTBL ORDER BY level DESC LIMIT 20;" 2>/dev/null
  echo ""
  echo -e "${Y}══ TỔNG THỐNG KÊ ══${N}"
  _mysql "SELECT COUNT(*) AS tong_nhan_vat FROM $CTBL;" 2>/dev/null
  local ATBL; ATBL=$(_acc_tbl)
  _mysql "SELECT COUNT(*) AS tong_tai_khoan FROM $ATBL;" 2>/dev/null
  read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _
}

# ── Broadcast thông báo server ───────────────────────────────────
admin_broadcast() {
  local BTBL; BTBL=$(_mysql "SHOW TABLES;" 2>/dev/null | grep -Ei "bang_tin|notice|announce|broadcast|thong_bao" | head -1)
  echo ""
  if [[ -z "$BTBL" ]]; then
    wrn "Không tìm thấy bảng thông báo"
    inf "Server Hashirama gõ lệnh trong game: /tb <nội dung>"
    read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _; return
  fi
  echo -e "${C}Bảng: $BTBL${N}"
  _mysql "DESCRIBE $BTBL;" 2>/dev/null
  read -p "$(echo -e "${C}Nội dung thông báo: ${N}")" msg
  _mysql "INSERT INTO $BTBL (content, created_at) VALUES ('$msg', NOW());" 2>/dev/null \
    && ok "Đã gửi thông báo!" || err "Thất bại"
  read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _
}

# ── Quản lý Bot NPC ──────────────────────────────────────────────
admin_bot() {
  local BTBL; BTBL=$(_mysql "SHOW TABLES;" 2>/dev/null | grep -Ei "bot|npc|mob_bot" | head -1)
  echo ""
  if [[ -z "$BTBL" ]]; then
    wrn "Không tìm thấy bảng bot/NPC"
    inf "Bot Hashirama được config trong file server, không qua DB"
    inf "Xem file: $NRO_HOME/bin/config/ hoặc gõ /bot trong game"
    read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _; return
  fi
  echo -e "${C}Bảng bot: $BTBL${N}"
  _mysql "SELECT * FROM $BTBL LIMIT 10;" 2>/dev/null
  echo ""
  echo -e "  ${Y}[1]${N} Thêm bot  ${Y}[2]${N} Xoá bot  ${Y}[3]${N} Bật/Tắt bot  ${Y}[0]${N} Quay lại"
  read -p "$(echo -e "${C}Chọn: ${N}")" bc
  case "$bc" in
    1) read -p "$(echo -e "${C}Tên bot: ${N}")" bn
       read -p "$(echo -e "${C}Map ID: ${N}")" bm
       _mysql "INSERT INTO $BTBL (name, map_id, active) VALUES ('$bn',$bm,1);" \
         && ok "Thêm bot '$bn' OK" || err "Thất bại";;
    2) read -p "$(echo -e "${C}Tên bot cần xoá: ${N}")" bn
       _mysql "DELETE FROM $BTBL WHERE name='$bn';" && ok "Xoá OK" || err "Thất bại";;
    3) read -p "$(echo -e "${C}Tên bot: ${N}")" bn
       read -p "$(echo -e "${C}Bật [1] / Tắt [0]: ${N}")" st
       _mysql "UPDATE $BTBL SET active=$st WHERE name='$bn';" && ok "OK" || err "Thất bại";;
  esac
  read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _
}

# ── Tạo / Quản lý tài khoản ──────────────────────────────────────
admin_account() {
  local ATBL; ATBL=$(_acc_tbl)
  [[ -z "$ATBL" ]] && { err "Không tìm thấy bảng account!"; sleep 2; return; }

  while true; do
    clear
    echo -e "${W}══════ QUẢN LÝ TÀI KHOẢN ══════${N}"
    echo -e "  ${Y}[1]${N} Đăng ký tài khoản mới"
    echo -e "  ${Y}[2]${N} Reset mật khẩu"
    echo -e "  ${Y}[3]${N} Ban tài khoản"
    echo -e "  ${Y}[4]${N} Unban tài khoản"
    echo -e "  ${Y}[5]${N} Set GM / Admin"
    echo -e "  ${Y}[6]${N} Danh sách tài khoản"
    echo -e "  ${Y}[7]${N} Xoá tài khoản"
    echo -e "  ${Y}[0]${N} Quay lại"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) read -p "$(echo -e "${C}Username: ${N}")" u
         read -s -p "$(echo -e "${C}Password: ${N}")" p; echo ""
         local h; h=$(echo -n "$p" | md5sum | cut -d' ' -f1)
         _mysql "INSERT INTO $ATBL (username,password,status) VALUES ('$u','$h',1);" \
           && ok "✓ Tạo tài khoản '$u'" || err "Thất bại (trùng username?)"
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      2) read -p "$(echo -e "${C}Username: ${N}")" u
         read -s -p "$(echo -e "${C}Pass mới: ${N}")" p; echo ""
         local h; h=$(echo -n "$p" | md5sum | cut -d' ' -f1)
         _mysql "UPDATE $ATBL SET password='$h' WHERE username='$u';" \
           && ok "Reset pass '$u' OK" || err "Thất bại"
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      3) read -p "$(echo -e "${C}Username: ${N}")" u
         _mysql "UPDATE $ATBL SET status=0 WHERE username='$u';" && ok "Đã ban '$u'" || err "Thất bại"
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      4) read -p "$(echo -e "${C}Username: ${N}")" u
         _mysql "UPDATE $ATBL SET status=1 WHERE username='$u';" && ok "Đã unban '$u'" || err "Thất bại"
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      5) read -p "$(echo -e "${C}Username: ${N}")" u
         # Thử các cột GM thường gặp
         _mysql "UPDATE $ATBL SET gm=1 WHERE username='$u';" 2>/dev/null \
           || _mysql "UPDATE $ATBL SET role='admin' WHERE username='$u';" 2>/dev/null \
           || _mysql "UPDATE $ATBL SET cap_do_gm=1 WHERE username='$u';" 2>/dev/null \
           && ok "Set GM cho '$u'" || wrn "Không rõ cột GM — thử SQL tuỳ ý"
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      6) echo ""
         _mysql "SELECT id,username,status FROM $ATBL ORDER BY id DESC LIMIT 30;" 2>/dev/null
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      7) read -p "$(echo -e "${R}Username cần xoá: ${N}")" u
         read -p "$(echo -e "${R}Xác nhận xoá '$u'? [y/N]: ${N}")" cf
         [[ "$cf" == "y" || "$cf" == "Y" ]] && \
           _mysql "DELETE FROM $ATBL WHERE username='$u';" && ok "Đã xoá '$u'" || wrn "Huỷ"
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      0) break;;
    esac
  done
}

# ── Quản lý nhân vật đầy đủ ──────────────────────────────────────
admin_char() {
  local CTBL; CTBL=$(_char_tbl)
  [[ -z "$CTBL" ]] && { err "Không tìm thấy bảng nhân vật!"; sleep 2; return; }

  while true; do
    clear
    echo -e "${W}══════ QUẢN LÝ NHÂN VẬT ══════${N}"
    echo -e "  ${Y}[1]${N} Nạp VÀNG"
    echo -e "  ${Y}[2]${N} Nạp NGỌC"
    echo -e "  ${Y}[3]${N} Set Level / EXP"
    echo -e "  ${Y}[4]${N} Cho Item"
    echo -e "  ${Y}[5]${N} Dịch chuyển nhân vật (đổi map)"
    echo -e "  ${Y}[6]${N} Reset vị trí (về map 1)"
    echo -e "  ${Y}[7]${N} Xoá nhân vật"
    echo -e "  ${Y}[8]${N} Top 20 nhân vật"
    echo -e "  ${Y}[9]${N} Xem nhân vật cụ thể"
    echo -e "  ${Y}[0]${N} Quay lại"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) admin_give "vang" "xu" "gold" "coin" "vàng";;
      2) admin_give "ngoc" "gem" "diamond" "ngọc";;
      3) admin_set_level;;
      4) admin_give_item;;
      5) read -p "$(echo -e "${C}Tên nhân vật: ${N}")" cn
         read -p "$(echo -e "${C}Map ID muốn đến: ${N}")" mid
         _mysql "UPDATE $CTBL SET map_id=$mid, pos_x=0, pos_y=0 WHERE name='$cn';" \
           && ok "Dịch chuyển '$cn' → map $mid" || err "Thất bại"
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      6) read -p "$(echo -e "${C}Tên nhân vật: ${N}")" cn
         _mysql "UPDATE $CTBL SET map_id=1, pos_x=0, pos_y=0 WHERE name='$cn';" \
           && ok "Reset vị trí '$cn' về map 1" || err "Thất bại"
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      7) read -p "$(echo -e "${R}Tên nhân vật cần xoá: ${N}")" cn
         read -p "$(echo -e "${R}Xác nhận xoá '$cn'? [y/N]: ${N}")" cf
         [[ "$cf" == "y" ]] && _mysql "DELETE FROM $CTBL WHERE name='$cn';" \
           && ok "Đã xoá '$cn'" || wrn "Huỷ"
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      8) admin_top;;
      9) read -p "$(echo -e "${C}Tên nhân vật: ${N}")" cn
         echo ""
         _mysql "SELECT * FROM $CTBL WHERE name='$cn';" 2>/dev/null
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      0) break;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# MAIN ADMIN MENU
# ══════════════════════════════════════════════════════════════════
admin_menu() {
  while true; do
    clear
    echo -e "${W}╔══════════════════════════════════╗${N}"
    echo -e "${W}║     BẢNG ĐIỀU KHIỂN ADMIN        ║${N}"
    echo -e "${W}╚══════════════════════════════════╝${N}"
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● DB: Online [$DB_NAME]${N}" \
      || echo -e "  ${R}● DB: Offline — chạy [1] Start Server trước${N}"
    echo ""
    echo -e "  ${C}── TÀI KHOẢN ──────────────────────${N}"
    echo -e "  ${Y}[1]${N} Quản lý tài khoản (đăng ký / ban / GM)"
    echo ""
    echo -e "  ${C}── NHÂN VẬT ───────────────────────${N}"
    echo -e "  ${Y}[2]${N} Quản lý nhân vật (vàng / ngọc / level / item)"
    echo ""
    echo -e "  ${C}── SERVER ─────────────────────────${N}"
    echo -e "  ${Y}[3]${N} Top BXH + thống kê server"
    echo -e "  ${Y}[4]${N} Broadcast thông báo toàn server"
    echo -e "  ${Y}[5]${N} Quản lý Bot / NPC"
    echo ""
    echo -e "  ${C}── NÂNG CAO ───────────────────────${N}"
    echo -e "  ${Y}[6]${N} Xem tất cả Tables DB"
    echo -e "  ${Y}[7]${N} SQL tuỳ ý (toàn quyền)"
    echo -e "  ${Y}[8]${N} Backup DB"
    echo -e "  ${Y}[9]${N} Xem log server"
    echo ""
    echo -e "  ${C}── GAME (lệnh gõ trong game) ──────${N}"
    echo -e "  ${Y}[h]${N} Hướng dẫn lệnh in-game admin"
    echo ""
    echo -e "  ${Y}[0]${N} Quay lại menu chính"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) admin_account;;
      2) admin_char;;
      3) admin_top;;
      4) admin_broadcast;;
      5) admin_bot;;
      6) echo ""; _mysql "SHOW TABLES;"; echo ""
         _mysql "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema='$DB_NAME' ORDER BY table_rows DESC;" 2>/dev/null
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      7) echo ""; _mysql "SHOW TABLES;"; echo ""
         read -p "$(echo -e "${C}Nhập SQL: ${N}")" sql
         [[ -n "$sql" ]] && _mysql "$sql"
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      8)
        local bk="$NRO_HOME/backup_$(date +%Y%m%d_%H%M).sql"
        inf "Backup DB → $bk"
        mysqldump -u root "$DB_NAME" > "$bk" 2>/dev/null \
          && ok "Backup OK: $(du -h "$bk" | cut -f1)" || err "Thất bại"
        read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      9) echo ""
         # Tìm log của server
         for lf in "$NRO_HOME/bin/log"* "$PREFIX/tmp/mysqld.err" "$NRO_HOME"/*.log; do
           [[ -f "$lf" ]] && { echo -e "${C}=== $lf ===${N}"; tail -20 "$lf"; echo ""; }
         done
         read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      h|H)
        clear
        echo -e "${W}══ LỆNH ADMIN TRONG GAME (Hashirama) ══${N}\n"
        echo -e "  Đăng nhập tài khoản GM rồi gõ trong chat:\n"
        echo -e "  ${Y}/tb <nội dung>${N}          → Thông báo toàn server"
        echo -e "  ${Y}/gold <tên> <số>${N}        → Nạp vàng"
        echo -e "  ${Y}/ngoc <tên> <số>${N}        → Nạp ngọc"
        echo -e "  ${Y}/level <tên> <lv>${N}       → Set level"
        echo -e "  ${Y}/kick <tên>${N}             → Kick khỏi server"
        echo -e "  ${Y}/ban <tên>${N}              → Ban nhân vật"
        echo -e "  ${Y}/unban <tên>${N}            → Unban"
        echo -e "  ${Y}/akill <tên>${N}            → Admin kill"
        echo -e "  ${Y}/tp <tên> <map>${N}         → Teleport"
        echo -e "  ${Y}/item <tên> <id> <sl>${N}   → Cho item"
        echo -e "  ${Y}/bot on|off${N}             → Bật/tắt bot"
        echo -e "  ${Y}/maintenance${N}            → Bảo trì server"
        echo -e "\n  ${C}Lệnh chính xác tuỳ version server.${N}"
        echo -e "  ${C}Gõ /help trong game để xem đầy đủ.${N}"
        read -p 

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    mysqladmin -u root ping 2>/dev/null | grep -q "alive" \
      && echo -e "  ${G}● MariaDB: Online${N}" \
      || echo -e "  ${Y}● MariaDB: Offline${N}"
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
\e[1;32m[Enter]...\e[0m' _;;
      0) break;;
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
    [[ -f "$APK_OUT" ]] \
      && echo -e "  ${G}● APK: Sẵn sàng${N}" \
      || echo -e "  ${Y}● APK: Chưa có${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin Tool (vàng/ngọc/ban...)"
    echo -e "  ${Y}[4]${N} Xem log MariaDB"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""; read -p "$(echo -e "${C}Chọn: ${N}")" ch
    case "$ch" in
      1) bash "$NRO_HOME/bin/start.sh"; read -p $'\e[1;32m[Enter]...\e[0m' _;;
      2) bash "$NRO_HOME/bin/stop.sh";  read -p $'\e[1;32m[Enter]...\e[0m' _;;
      3) admin_menu;;
      4) tail -30 "$PREFIX/tmp/mysqld.err" 2>/dev/null || err "Không có log"
         read -p $'\e[1;32m[Enter]...\e[0m' _;;
      0) echo -e "${G}Bye!${N}"; exit 0;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  inf "Đã setup xong — vào menu"
  main_menu; exit 0
fi

# ── FIRST RUN: TỰ ĐỘNG 6 BƯỚC ─────────────────────────────────────
echo -e "${W}  Lần đầu: tự động setup — không cần thao tác thêm${N}\n"

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages; echo ""

echo -e "${W}━━━ BƯỚC 2/6: Tải RAR từ Google Drive (~2.2GB) ━━━${N}"
step_download_rar || { err "Tải thất bại!"; exit 1; }; echo ""

echo -e "${W}━━━ BƯỚC 3/6: Giải nén APK + JARs + SQL ━━━━━━━━━${N}"
step_extract; echo ""

echo -e "${W}━━━ BƯỚC 4/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk; echo ""

echo -e "${W}━━━ BƯỚC 5/6: Setup MariaDB + import SQL ━━━━━━━━━${N}"
step_mariadb; echo ""

echo -e "${W}━━━ BƯỚC 6/6: Tạo launcher start/stop ━━━━━━━━━━━${N}"
step_create_launcher; echo ""

# Đánh dấu done
mkdir -p "$NRO_HOME"; date > "$SETUP_FLAG"

echo -e "${G}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                      ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $NRO_HOME/bin/start.sh"
echo ""
echo -e "  ${C}Bước tiếp:${N}"
echo -e "  1. Cài APK từ Downloads → ${Y}NRO_Hashirama.apk${N}"
echo -e "  2. Chọn ${Y}[1] Start Server${N} trong menu bên dưới"
echo -e "  3. Mở game → đăng nhập → chơi!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter vào menu chính...${N}")"
main_menu
