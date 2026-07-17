#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════╗
# ║   NRO HASHIRAMA — Auto Setup + Control Panel ║
# ║   Chơi offline 1 mình trên điện thoại        ║
# ║   v2.2 – Tải từ GitHub (~165MB, không RAR)   ║
# ╚══════════════════════════════════════════════╝

DIR="$HOME/nro"
LOG="$DIR/logs"
GAME_JAR="$DIR/game/Srcgame.jar"
LOGIN_JAR="$DIR/login/ServerLogin.jar"
APK_OUT="$DIR/Hashirama.apk"
SETUP_FLAG="$DIR/.setup_done"

# GitHub Release URLs (~165MB total)
GH_BASE="https://github.com/akah3674-glitch/rem3/releases/download/nro-v1.0"
URL_APK="$GH_BASE/Hashirama-Androi.apk"
URL_GAME="$GH_BASE/Srcgame.jar"
URL_LOGIN="$GH_BASE/ServerLogin.jar"
URL_SQL="$GH_BASE/nro_hashirama.sql"

# ── Màu sắc ──────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' W='\033[1;37m' N='\033[0m'
ok()   { echo -e "${G}  ✓${N}  $1"; }
err()  { echo -e "${R}  ✗${N}  $1"; }
warn() { echo -e "${Y}  !${N}  $1"; }
info() { echo -e "${B}  →${N}  $1"; }

# ── Tiêu đề + trạng thái (tính HẾT trước, clear sau → không nháy) ───
banner() {
    # Bước 1: thu thập dữ liệu (chậm) TRƯỚC KHI xóa màn hình
    local db_st game_st login_st sv_label sv_color
    mysqladmin ping -u root --silent --connect-timeout=1 >/dev/null 2>&1 \
        && db_st="${G}●${N}" || db_st="${R}●${N}"
    pgrep -f Srcgame.jar     >/dev/null 2>&1 \
        && game_st="${G}●${N}"  || game_st="${R}●${N}"
    pgrep -f ServerLogin.jar >/dev/null 2>&1 \
        && login_st="${G}●${N}" || login_st="${R}●${N}"
    if [[ "$game_st" == "${G}●${N}" && "$login_st" == "${G}●${N}" ]]; then
        sv_label="  ONLINE  "; sv_color="${G}"
    else
        sv_label="  OFFLINE "; sv_color="${R}"
    fi

    # Bước 2: xóa màn hình + in tất cả một lần (không có khoảng trễ sau clear)
    printf '\033[H\033[2J\033[3J'
    echo -e "${C}"
    echo "  ╔══════════════════════════════════════════╗"
    printf "  ║        NRO HASHIRAMA —${sv_color}%s${C}║\n" "$sv_label"
    echo "  ║     Private Server • Chơi 1 mình         ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${N}"
    echo -e "  DB $db_st  Login $login_st  Game $game_st   ${Y}IP: 127.0.0.1${N}"
    echo ""
}

# ── status_bar đã gộp vào banner() — giữ stub để không lỗi nếu còn gọi ──
status_bar() { :; }

# ── Tải file với wget (resume được) ──────────────
download_file() {
    local url="$1" out="$2" label="$3"
    info "Tải $label..."
    wget -q --show-progress -c -O "$out" "$url" 2>&1
    if [ -s "$out" ]; then
        ok "$label: $(du -sh "$out" | cut -f1)"
        return 0
    else
        err "Tải $label thất bại!"
        rm -f "$out"
        return 1
    fi
}

# ── Patch APK: thay IP → 127.0.0.1 ──────────────
patch_apk() {
    local src="$1" dst="$2"
    info "Patch IP server → 127.0.0.1 ..."
    python3 - "$src" "$dst" <<'PY'
import sys, zipfile, shutil

src, dst = sys.argv[1], sys.argv[2]
META = 'assets/bin/Data/Managed/Metadata/global-metadata.dat'

# Patch 1: Toàn bộ server entry (quan trọng: thay đúng format host:port)
# SAI: chỉ thay hostname → null bytes cắt mất ":14445"
# ĐÚNG: thay cả entry, null padding ở CUỐI
OLD1 = b'Hashirama:gatewayhashirama.nroacademy.online:14445:0,0,0'  # 56 bytes
_r1  = b'Hashirama:127.0.0.1:14445:0,0,0'
NEW1 = _r1 + b'\x00' * (len(OLD1) - len(_r1))

# Patch 2: Break gateway URL nrohashirama.online → domain không tồn tại
# Để game không fetch được server công cộng, phải dùng fallback 127.0.0.1
OLD2 = b'nrohashirama.online'   # 19 bytes
NEW2 = b'nrohashirama.local.'   # 19 bytes — DNS fail, game skip qua

try:
    with zipfile.ZipFile(src, 'r') as zin:
        if META not in zin.namelist():
            print("[!] Không tìm thấy metadata, copy thẳng")
            shutil.copy2(src, dst)
            sys.exit(0)
        meta = zin.read(META)

    patched = False
    if OLD1 in meta:
        meta = meta.replace(OLD1, NEW1, 1)
        print("[✓] Patch server entry: Hashirama → 127.0.0.1:14445")
        patched = True
    else:
        print("[!] Server entry không tìm thấy (có thể đã patch rồi)")

    if OLD2 in meta:
        meta = meta.replace(OLD2, NEW2, 1)
        print("[✓] Patch gateway URL: nrohashirama.online → nrohashirama.local.")
    else:
        print("[!] Gateway URL không tìm thấy (có thể đã patch rồi)")

    with zipfile.ZipFile(src, 'r') as zin, \
         zipfile.ZipFile(dst, 'w', allowZip64=True) as zout:
        for item in zin.infolist():
            if item.filename.startswith('META-INF/'):
                continue
            data = meta if item.filename == META else zin.read(item.filename)
            new_info = zipfile.ZipInfo(item.filename)
            new_info.compress_type = item.compress_type
            new_info.date_time = item.date_time
            new_info.external_attr = item.external_attr
            zout.writestr(new_info, data)
    print(f"[✓] APK patched → {dst}")

except Exception as e:
    print(f"[✗] Lỗi patch: {e}")
    shutil.copy2(src, dst)
PY
}

# ── Cấp quyền storage + copy APK sang Download ───
setup_storage() {
    # Đã có quyền rồi thì thôi
    [ -d "$HOME/storage/downloads" ] && return 0
    echo ""
    warn "Termux chưa có quyền truy cập bộ nhớ trong."
    echo -e "  ${Y}→ Sắp hiện hộp thoại xin quyền — bấm 'Cho phép'${N}"
    read -rp "  Nhấn Enter để tiếp tục..."
    termux-setup-storage
    # Chờ user cấp quyền (dialog async)
    local tries=0
    while [ ! -d "$HOME/storage/downloads" ]; do
        sleep 1; tries=$((tries+1))
        [ $tries -ge 15 ] && break
    done
    [ -d "$HOME/storage/downloads" ] && ok "Quyền storage OK" \
                                     || warn "Chưa cấp quyền — APK vẫn lưu ở ~/nro/"
}

copy_apk_sdcard() {
    local src="$1"
    local dst_name="Hashirama-NRO.apk"

    # Đảm bảo có quyền storage
    setup_storage

    # Thử tất cả đường dẫn Download phổ biến
    local dst=""
    for candidate in \
        "$HOME/storage/downloads/$dst_name" \
        "/sdcard/Download/$dst_name" \
        "/storage/emulated/0/Download/$dst_name" \
        "/sdcard/Downloads/$dst_name"
    do
        if [ -d "$(dirname "$candidate")" ]; then
            dst="$candidate"; break
        fi
    done

    if [ -n "$dst" ]; then
        cp "$src" "$dst" 2>/dev/null \
            && ok "APK → ${Y}$dst${N}" \
            || { warn "Copy thất bại, thử lại với tee...";
                 cat "$src" > "$dst" 2>/dev/null && ok "APK → ${Y}$dst${N}"; }
    else
        warn "Không copy được vào sdcard — dùng [9] Cài APK để cài trực tiếp"
    fi
}

# ── Sign APK: v1+v2 (apksigner) hoặc fallback jarsigner ─
sign_apk() {
    local apk="$1"
    local ks="$DIR/debug.keystore"
    info "Đang sign APK..."

    # Tạo keystore nếu chưa có
    if [ ! -f "$ks" ]; then
        keytool -genkeypair -alias nro -keyalg RSA -keysize 2048 -validity 10000 \
            -keystore "$ks" -storepass nro12345 -keypass nro12345 \
            -dname "CN=NRO,O=Private,C=VN" 2>/dev/null
    fi

    if command -v apksigner >/dev/null 2>&1; then
        # apksigner: v1 + v2 signature → Android 7+ chấp nhận
        apksigner sign \
            --ks "$ks" \
            --ks-pass pass:nro12345 \
            --key-pass pass:nro12345 \
            --v1-signing-enabled true \
            --v2-signing-enabled true \
            "$apk" 2>/dev/null
        ok "APK signed (v1+v2 — apksigner)"
    else
        # fallback jarsigner (chỉ v1, Android 6 trở xuống)
        local tmp="${apk%.apk}-signed.apk"
        jarsigner -keystore "$ks" -storepass nro12345 -keypass nro12345 \
            -sigalg SHA256withRSA -digestalg SHA-256 \
            -signedjar "$tmp" "$apk" nro 2>/dev/null && mv "$tmp" "$apk"
        warn "Signed v1 only (apksigner chưa cài) — có thể lỗi Android 7+"
    fi
}

# ── Cài môi trường ───────────────────────────────
install_env() {
    echo ""
    info "Cập nhật pkg..."
    pkg update -y -o Dpkg::Options::="--force-confold" >/dev/null 2>&1
    info "Cài Java + MariaDB + apksigner..."
    pkg install -y openjdk-17 mariadb wget apksigner >/dev/null 2>&1
    ok "Java + MariaDB + wget + apksigner OK"
}

# ── Khởi động MariaDB ────────────────────────────
start_db() {
    if mysqladmin ping -u root --silent >/dev/null 2>&1; then
        ok "MariaDB đang chạy"
        return 0
    fi
    info "Khởi động MariaDB..."
    [ ! -d "$PREFIX/var/lib/mysql/mysql" ] && mysql_install_db >/dev/null 2>&1
    mysqld_safe --datadir="$PREFIX/var/lib/mysql" \
        --socket="$PREFIX/tmp/mysql.sock" \
        --pid-file="$PREFIX/tmp/mysqld.pid" \
        >/dev/null 2>&1 &
    disown
    local tries=0
    while ! mysqladmin ping -u root --silent >/dev/null 2>&1; do
        sleep 2; tries=$((tries+1))
        [ $tries -ge 15 ] && { err "MariaDB không khởi động được!"; return 1; }
    done
    ok "MariaDB OK"
}

# ── Tạo DB + import SQL ──────────────────────────
init_db() {
    mysql -u root 2>/dev/null <<SQL
CREATE DATABASE IF NOT EXISTS hashirama CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON hashirama.* TO 'root'@'localhost';
FLUSH PRIVILEGES;
SQL
    ok "Database 'hashirama' OK"

    # Đảm bảo cột email có default (tránh lỗi INSERT khi tạo tài khoản)
    mysql -u root hashirama -e \
        "ALTER TABLE account MODIFY COLUMN email VARCHAR(255) NOT NULL DEFAULT '';" 2>/dev/null || true

    # Import SQL nếu chưa có bảng
    local tables
    tables=$(mysql -u root hashirama -e "SHOW TABLES;" 2>/dev/null | wc -l)
    if [ "$tables" -lt 5 ]; then
        local sql_file="$DIR/nro_hashirama.sql"
        if [ -f "$sql_file" ]; then
            info "Import dữ liệu game (~8MB)..."
            mysql -u root hashirama < "$sql_file" 2>/dev/null \
                && ok "SQL import OK ($(mysql -u root hashirama -e 'SHOW TABLES;' 2>/dev/null | wc -l) bảng)" \
                || warn "SQL import có lỗi nhỏ (bỏ qua)"
        fi
    else
        ok "DB đã có dữ liệu ($((tables-1)) bảng)"
    fi
}

write_configs() {
    mkdir -p "$DIR/login" "$DIR/game"

    cat > "$DIR/login/server.ini" <<INI
server.port=8888
db.port=3306
db.host=localhost
db.user=root
db.password=
db.name=hashirama
db.driver=com.mysql.cj.jdbc.Driver
admin.mode=0
INI

    cat > "$DIR/game/server.properties" <<PROP
server.db.ip=localhost
server.db.port=3306
server.db.name=hashirama
server.db.us=root
server.db.pw=
server.db.maxactive=99999
server.sv=1
server.port=14445
server.sv1=Hashirama:127.0.0.1:14445:0,0,0
server.waitlogin=5
server.maxperip=99
server.maxplayer=1
server.expserver=1
server.debug=false
server.name=Hashirama
api.port=8080
api.key=abcdefJKLMNOPQR@STUVWXYrstuv@wABCDEF@GZabxyz
server.hikari.minIdle=2
server.hikari.poolSize=10
server.hikari.cachePre=true
server.hikari.cacheSize=250
server.hikari.cacheSqlLimit=2048
PROP
    ok "Config đã tạo"
}

# ══════════════════════════════════════════════════
# MENU ACTIONS
# ══════════════════════════════════════════════════

do_full_setup() {
    banner
    echo -e "  ${C}════ FULL SETUP — Tải ~165MB từ GitHub ════${N}"
    echo ""
    echo -e "  ${W}Bước 1/4:${N} Cài Java + MariaDB"
    echo -e "  ${W}Bước 2/4:${N} Tải APK game (129MB) + patch IP"
    echo -e "  ${W}Bước 3/4:${N} Tải Server JARs + SQL (36MB)"
    echo -e "  ${W}Bước 4/4:${N} Cài MariaDB + import dữ liệu"
    echo ""
    echo -e "  ${Y}Tổng: ~165MB (thay vì 2.2GB RAR)${N}"
    echo ""
    read -rp "  Nhấn Enter để bắt đầu..."
    echo ""

    mkdir -p "$DIR/game" "$DIR/login" "$LOG"

    # Bước 1: Cài packages
    echo -e "${W}  ─── BƯỚC 1/4: Cài packages ───${N}"
    install_env

    # Bước 2: Tải + patch + sign APK
    echo ""
    echo -e "${W}  ─── BƯỚC 2/4: Tải APK game (129MB) ───${N}"
    local apk_raw="$DIR/Hashirama-orig.apk"
    local apk_patched="$DIR/Hashirama-patched.apk"

    if [ ! -s "$apk_raw" ]; then
        download_file "$URL_APK" "$apk_raw" "APK Hashirama" \
            || { err "Không tải được APK!"; read -rp "  Enter..."; return; }
    else
        ok "APK đã có ($(du -sh "$apk_raw" | cut -f1))"
    fi

    patch_apk "$apk_raw" "$apk_patched"
    if [ -s "$apk_patched" ]; then
        mv "$apk_patched" "$APK_OUT"
        ok "Patch IP OK"
    else
        warn "Patch lỗi, dùng APK gốc"
        cp "$apk_raw" "$APK_OUT"
    fi
    sign_apk "$APK_OUT"
    rm -f "$apk_raw" "$apk_patched"

    # Copy APK sang sdcard/Download để dễ cài
    copy_apk_sdcard "$APK_OUT"

    # Bước 3: Tải JARs + SQL
    echo ""
    echo -e "${W}  ─── BƯỚC 3/4: Tải Server JARs + SQL (36MB) ───${N}"
    [ ! -s "$GAME_JAR" ]  \
        && download_file "$URL_GAME"  "$GAME_JAR"  "Srcgame.jar" \
        || ok "Srcgame.jar đã có"
    [ ! -s "$LOGIN_JAR" ] \
        && download_file "$URL_LOGIN" "$LOGIN_JAR" "ServerLogin.jar" \
        || ok "ServerLogin.jar đã có"
    [ ! -s "$DIR/nro_hashirama.sql" ] \
        && download_file "$URL_SQL" "$DIR/nro_hashirama.sql" "SQL database" \
        || ok "SQL đã có"

    # Bước 4: DB + config
    echo ""
    echo -e "${W}  ─── BƯỚC 4/4: Cài MariaDB + import dữ liệu ───${N}"
    start_db || { read -rp "  Enter..."; return; }
    init_db
    write_configs

    touch "$SETUP_FLAG"
    echo ""
    echo -e "  ${G}══════════════════════════════════════${N}"
    ok "SETUP HOÀN TẤT!"
    echo -e "  ${G}══════════════════════════════════════${N}"
    echo ""
    echo -e "  ${W}APK cài game:${N}  ${Y}$APK_OUT${N}"
    echo -e "  ${W}Bước tiếp:${N}     [2] Bật server → cài APK → chơi!"
    echo ""
    read -rp "  Nhấn Enter để về menu..."
}

do_start() {
    banner
    echo -e "  ${C}════ BẬT SERVER ════${N}"
    echo ""

    [ ! -f "$GAME_JAR" ]  && { err "Thiếu Srcgame.jar — chạy [1] Setup trước";  read -rp "  Enter..."; return; }
    [ ! -f "$LOGIN_JAR" ] && { err "Thiếu ServerLogin.jar — chạy [1] Setup trước"; read -rp "  Enter..."; return; }

    start_db || { read -rp "  Enter..."; return; }

    # Fix schema: đảm bảo email có default dù DB cũ hay mới
    mysql -u root hashirama -e \
        "ALTER TABLE account MODIFY COLUMN email VARCHAR(255) NOT NULL DEFAULT '';" 2>/dev/null || true

    # Hàm chờ port mở (tối đa wait_sec giây)
    wait_port() {
        local port="$1" label="$2" wait_sec="${3:-15}"
        local tries=0
        while [ $tries -lt $wait_sec ]; do
            if (echo > /dev/tcp/127.0.0.1/$port) 2>/dev/null; then
                ok "$label ON (port $port)"
                return 0
            fi
            sleep 1; tries=$((tries+1))
        done
        err "$label KHÔNG khởi động được sau ${wait_sec}s — xem log: $LOG/"
        return 1
    }

    # Login server
    if ! pgrep -f ServerLogin.jar >/dev/null 2>&1; then
        cd "$DIR/login" || true
        java -jar ServerLogin.jar > "$LOG/login.log" 2>&1 &
        disown
        info "Chờ Login server (port 8888)..."
        wait_port 8888 "Login server" 20 || true
    else
        warn "Login server đang chạy rồi"
    fi

    # Game server
    if ! pgrep -f Srcgame.jar >/dev/null 2>&1; then
        cd "$DIR/game" || true
        java -Xms128m -Xmx256m -jar Srcgame.jar > "$LOG/game.log" 2>&1 &
        disown
        info "Chờ Game server (port 14445)..."
        wait_port 14445 "Game server" 25 || true
    else
        warn "Game server đang chạy rồi"
    fi

    echo ""
    echo -e "  ${W}★ Mở game Hashirama → đăng ký → chơi!${N}"
    echo ""
    read -rp "  Nhấn Enter..."
}

do_stop() {
    banner
    echo -e "  ${C}════ TẮT SERVER ════${N}"
    echo ""
    pkill -f Srcgame.jar     2>/dev/null && ok "Game server OFF"  || warn "Game server chưa chạy"
    pkill -f ServerLogin.jar 2>/dev/null && ok "Login server OFF" || warn "Login server chưa chạy"
    mysqladmin shutdown -u root 2>/dev/null && ok "MariaDB OFF"   || warn "MariaDB chưa chạy"
    echo ""
    read -rp "  Nhấn Enter..."
}

do_status() {
    banner
    echo -e "  ${C}════ TRẠNG THÁI ════${N}"
    echo ""

    mysqladmin ping -u root --silent >/dev/null 2>&1 \
        && ok "MariaDB: ĐANG CHẠY" || err "MariaDB: TẮT"
    pgrep -f ServerLogin.jar >/dev/null 2>&1 \
        && ok "Login server: ĐANG CHẠY (port 8888)" || err "Login server: TẮT"
    pgrep -f Srcgame.jar >/dev/null 2>&1 \
        && ok "Game server: ĐANG CHẠY (port 14445)" || err "Game server: TẮT"

    echo ""
    [ -f "$APK_OUT" ] \
        && ok "APK: $APK_OUT ($(du -sh "$APK_OUT" | cut -f1))" \
        || warn "APK: chưa có (cần chạy [1] Setup)"

    echo ""
    echo -e "  ${C}── Log game (10 dòng cuối) ──${N}"
    [ -f "$LOG/game.log" ] && tail -10 "$LOG/game.log" || echo "  (chưa có log)"
    echo ""
    read -rp "  Nhấn Enter..."
}

do_log() {
    banner
    echo -e "  ${C}════ XEM LOG LIVE ════${N}"
    echo -e "  ${Y}Ctrl+C để thoát${N}"
    echo ""
    if [ -f "$LOG/game.log" ]; then
        tail -f "$LOG/game.log"
    else
        warn "Chưa có log game"
        read -rp "  Enter..."
    fi
}

# ══════════════════════════════════════════════════
# ADMIN TOOL
# ── Schema thực tế (SQL nrofree2025):
#    account : id, username, password, ban (0=OK 1=banned)
#    player  : id, account_id, name, power, thoi_vang, ...
# ══════════════════════════════════════════════════
_db()  { mysql -u root hashirama -e "$1" 2>/dev/null; }
_dbq() { mysql -u root hashirama -Ne "$1" 2>/dev/null; }   # no header
# _dbe: như _db nhưng in ra lỗi MySQL (dùng cho create/update quan trọng)
_dbe() { mysql -u root hashirama -e "$1" 2>&1; }

admin_give_thoi_vang() {
    echo ""
    read -rp "  Tên nhân vật: " cname
    read -rp "  Số thỏi vàng nạp: " amount
    local exist
    exist=$(_dbq "SELECT COUNT(*) FROM player WHERE name='$cname';")
    if [ "$exist" = "0" ] || [ -z "$exist" ]; then
        err "Không tìm thấy nhân vật '$cname'!"
    else
        _db "UPDATE player SET thoi_vang = thoi_vang + $amount WHERE name='$cname';" \
            && ok "Đã nạp $amount thỏi vàng cho '$cname'!" || err "Thất bại!"
        _db "SELECT name, power, thoi_vang FROM player WHERE name='$cname';"
    fi
    read -rp "  [Enter]..."
}

admin_give_power() {
    echo ""
    read -rp "  Tên nhân vật: " cname
    read -rp "  Power thêm vào: " amount
    local exist
    exist=$(_dbq "SELECT COUNT(*) FROM player WHERE name='$cname';")
    if [ "$exist" = "0" ] || [ -z "$exist" ]; then
        err "Không tìm thấy nhân vật '$cname'!"
    else
        _db "UPDATE player SET power = power + $amount WHERE name='$cname';" \
            && ok "Đã tăng $amount power cho '$cname'!" || err "Thất bại!"
        _db "SELECT name, power, thoi_vang FROM player WHERE name='$cname';"
    fi
    read -rp "  [Enter]..."
}

admin_menu() {
    while true; do
        banner
        echo -e "  ${W}══════ ADMIN TOOL ══════${N}"
        echo ""
        mysqladmin ping -u root --silent >/dev/null 2>&1 \
            && echo -e "  ${G}● DB: Online${N}" \
            || echo -e "  ${R}● DB: Offline — chạy [2] Bật server trước${N}"
        echo ""
        echo -e "  ${Y}[1]${N} Nạp Thỏi Vàng (thoi_vang)"
        echo -e "  ${Y}[2]${N} Tăng Power"
        echo -e "  ${Y}[3]${N} Danh sách nhân vật (top power)"
        echo -e "  ${Y}[4]${N} Tạo tài khoản"
        echo -e "  ${Y}[5]${N} Reset mật khẩu"
        echo -e "  ${Y}[6]${N} Ban / Unban"
        echo -e "  ${Y}[7]${N} SQL tuỳ ý"
        echo -e "  ${Y}[0]${N} Quay lại"
        echo ""
        read -r -p "  Chọn: " ch
        case "$ch" in
            1) admin_give_thoi_vang ;;
            2) admin_give_power ;;
            3)
                echo ""
                _db "SELECT p.name, p.power, p.thoi_vang, a.username
                     FROM player p
                     LEFT JOIN account a ON p.account_id = a.id
                     ORDER BY p.power DESC LIMIT 20;"
                read -rp "  [Enter]..."
                ;;
            4)
                echo ""
                read -rp "  Username: " u
                read -s -p "  Password: " p; echo ""
                local h
                h=$(echo -n "$p" | md5sum | cut -d' ' -f1)
                # Dùng _dbe để lỗi SQL hiện rõ (trùng username, bảng sai, v.v.)
                local result
                result=$(_dbe "INSERT INTO account (username, password, email) VALUES ('$u','$h','$u@nro.local');")
                if echo "$result" | grep -qi "error\|ERROR"; then
                    err "Tạo tài khoản thất bại:"
                    echo "$result"
                else
                    ok "Tạo tài khoản '$u' OK!"
                fi
                read -rp "  [Enter]..."
                ;;
            5)
                echo ""
                read -rp "  Username: " u
                read -s -p "  Pass mới: " p; echo ""
                local h
                h=$(echo -n "$p" | md5sum | cut -d' ' -f1)
                _db "UPDATE account SET password='$h' WHERE username='$u';" \
                    && ok "Đổi pass '$u' OK!" || err "Thất bại!"
                read -rp "  [Enter]..."
                ;;
            6)
                echo ""
                read -rp "  Username: " u
                echo -e "  ${Y}[1]${N} Ban  ${Y}[2]${N} Unban"
                read -r -p "  Chọn: " bc
                if [ "$bc" = "1" ]; then
                    _db "UPDATE account SET ban=1 WHERE username='$u';" && ok "Đã ban '$u'"
                elif [ "$bc" = "2" ]; then
                    _db "UPDATE account SET ban=0 WHERE username='$u';" && ok "Đã unban '$u'"
                fi
                read -rp "  [Enter]..."
                ;;
            7)
                echo ""
                echo -e "  ${C}Tables:${N}"
                _db "SHOW TABLES;"
                echo ""
                read -rp "  SQL: " sql
                [[ -n "$sql" ]] && _db "$sql"
                read -rp "  [Enter]..."
                ;;
            0) break ;;
        esac
    done
}

do_install_apk() {
    banner
    echo -e "  ${C}════ CÀI APK TRỰC TIẾP ════${N}"
    echo ""

    # ── Bước 1: Xoá tất cả file APK cũ ─────────────────────────────
    info "Xoá file APK cũ..."
    rm -f "$APK_OUT" \
          "$HOME/storage/downloads/Hashirama-NRO.apk" \
          "$HOME/storage/downloads/Hashirama-Androi.apk" \
          "/sdcard/Download/Hashirama-NRO.apk" \
          "/sdcard/Download/Hashirama-Androi.apk" 2>/dev/null
    ok "Đã xoá file cũ"

    # ── Bước 2: Gỡ app cũ khỏi máy ─────────────────────────────────
    info "Gỡ cài đặt app cũ (nếu có)..."
    pm uninstall com.Hashirama.Hashirama >/dev/null 2>&1 \
        && ok "Đã gỡ app cũ" \
        || warn "App chưa cài hoặc đã gỡ rồi — OK"
    echo ""

    # ── Bước 3: Tải APK đã patch+sign sẵn từ GitHub ─────────────────
    # APK trên GitHub đã được patch IP 127.0.0.1:14445 và sign sẵn
    info "Đang tải APK (~129MB) từ GitHub..."
    echo -e "  ${Y}Vui lòng đợi...${N}"

    if ! download_file "$URL_APK" "$APK_OUT" "Hashirama APK"; then
        err "Tải APK thất bại — kiểm tra mạng rồi thử lại"
        read -rp "  Enter..."; return
    fi

    # Copy ra sdcard để dùng file manager nếu cần
    copy_apk_sdcard "$APK_OUT"

    echo ""
    ok "APK sẵn sàng: $(du -sh "$APK_OUT" | cut -f1)"
    echo ""

    # ── Bước 4: Mở dialog cài ───────────────────────────────────────
    if command -v termux-open >/dev/null 2>&1; then
        info "Mở dialog cài đặt..."
        termux-open --content-type application/vnd.android.package-archive "$APK_OUT" 2>/dev/null &
        disown
        ok "Hộp thoại cài APK đã mở!"
    else
        am start -a android.intent.action.VIEW \
            -d "file://$APK_OUT" \
            -t application/vnd.android.package-archive \
            --flags 0x10000001 >/dev/null 2>&1 &
        disown
        ok "Đã gọi trình cài APK!"
    fi

    echo -e "  ${Y}→ Bấm 'Cài đặt' trên màn hình điện thoại${N}"
    echo ""
    echo -e "  ${W}Nếu hộp thoại không hiện, mở file manager → Download → Hashirama-NRO.apk${N}"
    echo ""
    read -rp "  Nhấn Enter..."
}

do_clean() {
    banner
    echo -e "  ${C}════ DỌN FILE THỪA ════${N}"
    echo ""

    local total=0
    _show() {
        local f="$1" label="$2"
        if [ -f "$f" ]; then
            local sz; sz=$(du -sh "$f" 2>/dev/null | cut -f1)
            echo -e "  ${Y}[$sz]${N} $label"
            echo "    $f"
        fi
    }

    echo -e "  ${W}Có thể xoá:${N}"
    _show "$DIR/nro_hashirama.sql"   "SQL dump (chỉ cần lúc import, DB đã có rồi)"
    _show "$DIR/Hashirama-orig.apk"  "APK gốc chưa patch (file tạm)"
    _show "$DIR/Hashirama-patched.apk" "APK patched chưa sign (file tạm)"
    _show "$DIR/debug.keystore"      "Keystore tự tạo (tái tạo được)"

    echo ""
    echo -e "  ${W}Không xoá:${N} Hashirama.apk · Srcgame.jar · ServerLogin.jar · logs"
    echo ""
    read -rp "  Xoá hết những file trên? [y/N]: " yn
    [[ "$yn" != "y" && "$yn" != "Y" ]] && { warn "Huỷ"; read -rp "  Enter..."; return; }

    echo ""
    local freed=0
    _del() {
        local f="$1" label="$2"
        if [ -f "$f" ]; then
            local bytes; bytes=$(stat -c%s "$f" 2>/dev/null || echo 0)
            rm -f "$f" && ok "Xoá: $label ($(( bytes/1024/1024 ))MB)" \
                       || warn "Không xoá được: $f"
            freed=$(( freed + bytes ))
        fi
    }

    _del "$DIR/nro_hashirama.sql"      "nro_hashirama.sql"
    _del "$DIR/Hashirama-orig.apk"     "Hashirama-orig.apk"
    _del "$DIR/Hashirama-patched.apk"  "Hashirama-patched.apk"
    _del "$DIR/debug.keystore"         "debug.keystore"

    # Xoá log cũ nếu > 10MB
    local log_sz
    log_sz=$(du -sb "$LOG" 2>/dev/null | cut -f1 || echo 0)
    if [ "$log_sz" -gt 10485760 ]; then
        > "$LOG/game.log"; > "$LOG/login.log"
        ok "Xoá log cũ (> 10MB)"
    fi

    echo ""
    ok "Đã giải phóng ~$(( freed/1024/1024 ))MB"
    read -rp "  Nhấn Enter..."
}

do_reset_data() {
    banner
    echo -e "  ${C}════ XOÁ DỮ LIỆU ════${N}"
    echo ""
    warn "Xoá toàn bộ dữ liệu game (account + nhân vật)?"
    read -rp "  Gõ 'yes' để xác nhận: " confirm
    if [ "$confirm" = "yes" ]; then
        mysqladmin ping -u root --silent >/dev/null 2>&1 || start_db
        mysql -u root 2>/dev/null <<SQL
DROP DATABASE IF EXISTS hashirama;
CREATE DATABASE hashirama CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON hashirama.* TO 'root'@'localhost';
FLUSH PRIVILEGES;
SQL
        [ -f "$DIR/nro_hashirama.sql" ] \
            && mysql -u root hashirama < "$DIR/nro_hashirama.sql" 2>/dev/null \
            && ok "DB reset + import lại OK" \
            || ok "DB reset OK (không có SQL file)"
    else
        warn "Huỷ"
    fi
    read -rp "  Nhấn Enter..."
}

# ══════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════
main_menu() {
    while true; do
        banner
        status_bar

        if [ -f "$SETUP_FLAG" ]; then
            local jar_ok apk_ok
            [ -f "$GAME_JAR" ]  && jar_ok="${G}OK${N}" || jar_ok="${R}THIẾU${N}"
            [ -f "$APK_OUT" ]   && apk_ok="${G}OK${N}" || apk_ok="${R}THIẾU${N}"
            echo -e "  JAR: $jar_ok  •  APK: $apk_ok"
            echo ""
        fi

        echo -e "  ${W}[1]${N} 📦  Setup / Tải lại files"
        echo -e "  ${W}[2]${N} ▶   Bật server"
        echo -e "  ${W}[3]${N} ■   Tắt server"
        echo -e "  ${W}[4]${N} 📊  Trạng thái"
        echo -e "  ${W}[5]${N} 📜  Xem log live"
        echo -e "  ${W}[6]${N} 👑  Admin tool"
        echo -e "  ${W}[7]${N} 🗑   Xoá dữ liệu game"
        echo -e "  ${W}[8]${N} 🧹  Dọn file thừa (giải phóng bộ nhớ)"
        echo -e "  ${W}[9]${N} 📲  Cài APK trực tiếp (không cần file manager)"
        echo -e "  ${W}[0]${N} ✗   Thoát"
        echo ""
        read -r -p "  Chọn: " choice

        case "$choice" in
            1) do_full_setup ;;
            2) do_start ;;
            3) do_stop ;;
            4) do_status ;;
            5) do_log ;;
            6) admin_menu ;;
            7) do_reset_data ;;
            8) do_clean ;;
            9) do_install_apk ;;
            0) echo ""; exit 0 ;;
            *) ;;
        esac
    done
}

# ── Khởi chạy ────────────────────────────────────
mkdir -p "$DIR/game" "$DIR/login" "$LOG"
main_menu
