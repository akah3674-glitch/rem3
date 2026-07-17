#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════╗
# ║   NRO HASHIRAMA — Auto Setup + Control Panel ║
# ║   Chơi offline 1 mình trên điện thoại        ║
# ║   v2.0 – Tải từ GitHub (~165MB, không RAR)   ║
# ╚══════════════════════════════════════════════╝

DIR="$HOME/nro"
LOG="$DIR/logs"
GAME_JAR="$DIR/game/Srcgame.jar"
LOGIN_JAR="$DIR/login/ServerLogin.jar"
APK_OUT="$DIR/Hashirama.apk"
SETUP_FLAG="$DIR/.setup_done"

# GitHub Release URLs (~165MB total, không cần tải RAR 2.2GB)
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

# ── Tiêu đề ──────────────────────────────────────
banner() {
    clear
    echo -e "${C}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║        NRO HASHIRAMA — OFFLINE           ║"
    echo "  ║     Private Server • Chơi 1 mình         ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${N}"
}

# ── Trạng thái nhanh ─────────────────────────────
status_bar() {
    local db_st game_st login_st
    mysqladmin ping -u root --silent 2>/dev/null && db_st="${G}●${N}" || db_st="${R}●${N}"
    pgrep -f Srcgame.jar    >/dev/null 2>&1 && game_st="${G}●${N}"  || game_st="${R}●${N}"
    pgrep -f ServerLogin.jar >/dev/null 2>&1 && login_st="${G}●${N}" || login_st="${R}●${N}"
    echo -e "  DB $db_st  Login $login_st  Game $game_st   ${Y}IP: 127.0.0.1${N}"
    echo ""
}

# ── Tải file với wget (resume được) ──────────────
download_file() {
    local url="$1" out="$2" label="$3"
    info "Tải $label..."
    wget -q --show-progress -c -O "$out" "$url" 2>&1
    if [ -s "$out" ]; then
        ok "$label: $(du -sh $out | cut -f1)"
        return 0
    else
        err "Tải $label thất bại!"
        rm -f "$out"
        return 1
    fi
}

# ── Sign APK bằng debug key ──────────────────────
sign_apk() {
    local apk="$1"
    local ks="$DIR/debug.keystore"
    info "Đang sign APK..."
    if [ ! -f "$ks" ]; then
        keytool -genkeypair -alias nro -keyalg RSA -keysize 2048 -validity 10000 \
            -keystore "$ks" -storepass nro12345 -keypass nro12345 \
            -dname "CN=NRO,O=Private,C=VN" 2>/dev/null
    fi
    local tmp="${apk%.apk}-signed.apk"
    jarsigner -keystore "$ks" -storepass nro12345 -keypass nro12345 \
        -sigalg SHA256withRSA -digestalg SHA-256 \
        -signedjar "$tmp" "$apk" nro 2>/dev/null && mv "$tmp" "$apk"
    ok "APK signed"
}

# ── Cài môi trường ───────────────────────────────
install_env() {
    echo ""
    info "Cập nhật pkg..."
    pkg update -y -o Dpkg::Options::="--force-confold" >/dev/null 2>&1
    info "Cài Java + MariaDB..."
    pkg install -y openjdk-17 mariadb wget >/dev/null 2>&1
    ok "Java + MariaDB + wget OK"
}

# ── Khởi động MariaDB ────────────────────────────
start_db() {
    if mysqladmin ping -u root --silent 2>/dev/null; then
        ok "MariaDB đang chạy"
        return 0
    fi
    info "Khởi động MariaDB..."
    [ ! -d "$PREFIX/var/lib/mysql/mysql" ] && mysql_install_db >/dev/null 2>&1
    mysqld_safe --datadir="$PREFIX/var/lib/mysql" >/dev/null 2>&1 &
    disown
    local tries=0
    while ! mysqladmin ping -u root --silent 2>/dev/null; do
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

    # Import SQL nếu chưa có bảng
    local tables
    tables=$(mysql -u root hashirama -e "SHOW TABLES;" 2>/dev/null | wc -l)
    if [ "$tables" -lt 5 ]; then
        local sql_file="$DIR/nro_hashirama.sql"
        if [ -f "$sql_file" ]; then
            info "Import dữ liệu game (~8MB)..."
            mysql -u root hashirama < "$sql_file" 2>/dev/null && ok "SQL import OK" || warn "SQL import có lỗi nhỏ (bỏ qua)"
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
    echo -e "  ${W}Bước 2/4:${N} Tải APK game (129MB)"
    echo -e "  ${W}Bước 3/4:${N} Tải Server JARs + SQL (36MB)"
    echo -e "  ${W}Bước 4/4:${N} Cài MariaDB + import dữ liệu"
    echo ""
    echo -e "  ${Y}Tổng: ~165MB (thay vì 2.2GB)${N}"
    echo ""
    read -p "  Nhấn Enter để bắt đầu..."
    echo ""

    mkdir -p "$DIR/game" "$DIR/login" "$LOG"

    # Bước 1: Cài packages
    echo -e "${W}  ─── BƯỚC 1/4: Cài packages ───${N}"
    install_env

    # Bước 2: Tải APK
    echo ""
    echo -e "${W}  ─── BƯỚC 2/4: Tải APK game (129MB) ───${N}"
    local apk_raw="$DIR/Hashirama-orig.apk"
    if [ ! -s "$apk_raw" ]; then
        download_file "$URL_APK" "$apk_raw" "APK Hashirama" || { err "Không tải được APK!"; read -p "  Enter..."; return; }
    else
        ok "APK đã có ($(du -sh $apk_raw | cut -f1))"
    fi

    # Patch IP → 127.0.0.1
    info "Patch IP server → 127.0.0.1 ..."
    local apk_patched="$DIR/Hashirama-patched.apk"
    python3 - "$apk_raw" "$apk_patched" <<'PY'
import sys, zipfile, os
src, dst = sys.argv[1], sys.argv[2]
META = 'assets/bin/Data/Managed/Metadata/global-metadata.dat'
OLD  = b'gatewayhashirama.nroacademy.online'   # 35 bytes
NEW  = b'127.0.0.1' + b'\x00' * (len(OLD) - len(b'127.0.0.1'))

with zipfile.ZipFile(src, 'r') as zin:
    if META not in zin.namelist():
        print("[!] Không tìm thấy metadata, copy thẳng")
        import shutil; shutil.copy2(src, dst); sys.exit(0)
    meta = zin.read(META)

if OLD in meta:
    meta_new = meta.replace(OLD, NEW, 1)
    print(f"[✓] Đã thay IP: {OLD.rstrip(b'chr(0)')} → 127.0.0.1")
else:
    meta_new = meta
    print("[!] Không tìm thấy IP cũ (có thể đã patch)")

with zipfile.ZipFile(src,'r') as zin, \
     zipfile.ZipFile(dst,'w',zipfile.ZIP_STORED,allowZip64=True) as zout:
    for item in zin.infolist():
        if item.filename.startswith('META-INF/'): continue
        data = meta_new if item.filename == META else zin.read(item.filename)
        zout.writestr(zipfile.ZipInfo(item.filename), data)
print(f"[✓] APK patched: {dst}")
PY

    if [ -s "$apk_patched" ]; then
        cp "$apk_patched" "$APK_OUT"
        rm -f "$apk_patched"
        ok "Patch IP OK"
    else
        warn "Patch thất bại, dùng APK gốc"
        cp "$apk_raw" "$APK_OUT"
    fi

    # Sign APK
    sign_apk "$APK_OUT"
    rm -f "$apk_raw"

    # Bước 3: Tải JARs + SQL
    echo ""
    echo -e "${W}  ─── BƯỚC 3/4: Tải Server JARs + SQL (36MB) ───${N}"
    [ ! -s "$GAME_JAR" ]  && download_file "$URL_GAME"  "$GAME_JAR"  "Srcgame.jar"     || ok "Srcgame.jar đã có"
    [ ! -s "$LOGIN_JAR" ] && download_file "$URL_LOGIN" "$LOGIN_JAR" "ServerLogin.jar" || ok "ServerLogin.jar đã có"
    [ ! -s "$DIR/nro_hashirama.sql" ] && download_file "$URL_SQL" "$DIR/nro_hashirama.sql" "SQL database" || ok "SQL đã có"

    # Bước 4: DB + config
    echo ""
    echo -e "${W}  ─── BƯỚC 4/4: Cài MariaDB + import dữ liệu ───${N}"
    start_db || { read -p "  Enter..."; return; }
    init_db
    write_configs

    # Done
    touch "$SETUP_FLAG"
    echo ""
    echo -e "  ${G}══════════════════════════════════════${N}"
    ok "SETUP HOÀN TẤT!"
    echo -e "  ${G}══════════════════════════════════════${N}"
    echo ""
    echo -e "  ${W}APK cài game:${N}  ${Y}$APK_OUT${N}"
    echo -e "  ${W}Bước tiếp:${N}     Chọn [2] Bật server, rồi cài APK"
    echo ""
    read -p "  Nhấn Enter để về menu..."
}

do_start() {
    banner
    echo -e "  ${C}════ BẬT SERVER ════${N}"
    echo ""

    [ ! -f "$GAME_JAR" ]  && { err "Thiếu Srcgame.jar — chạy [1] Setup trước"; read -p "  Enter..."; return; }
    [ ! -f "$LOGIN_JAR" ] && { err "Thiếu ServerLogin.jar — chạy [1] Setup trước"; read -p "  Enter..."; return; }

    start_db || { read -p "  Enter..."; return; }
    init_db

    # Login server
    if ! pgrep -f ServerLogin.jar >/dev/null 2>&1; then
        cd "$DIR/login"
        java -jar ServerLogin.jar > "$LOG/login.log" 2>&1 &
        disown
        sleep 2
        ok "Login server ON (port 8888)"
    else
        warn "Login server đang chạy rồi"
    fi

    # Game server
    if ! pgrep -f Srcgame.jar >/dev/null 2>&1; then
        cd "$DIR/game"
        java -Xms128m -Xmx256m -jar Srcgame.jar > "$LOG/game.log" 2>&1 &
        disown
        sleep 3
        ok "Game server ON (port 14445)"
    else
        warn "Game server đang chạy rồi"
    fi

    echo ""
    echo -e "  ${W}★ Mở game Hashirama → đăng ký → chơi!${N}"
    echo ""
    read -p "  Nhấn Enter..."
}

do_stop() {
    banner
    echo -e "  ${C}════ TẮT SERVER ════${N}"
    echo ""
    pkill -f Srcgame.jar     2>/dev/null && ok "Game server OFF"     || warn "Game server chưa chạy"
    pkill -f ServerLogin.jar 2>/dev/null && ok "Login server OFF"    || warn "Login server chưa chạy"
    mysqladmin shutdown -u root 2>/dev/null && ok "MariaDB OFF" || warn "MariaDB chưa chạy"
    echo ""
    read -p "  Nhấn Enter..."
}

do_status() {
    banner
    echo -e "  ${C}════ TRẠNG THÁI ════${N}"
    echo ""

    if mysqladmin ping -u root --silent 2>/dev/null; then
        ok "MariaDB: ĐANG CHẠY"
    else
        err "MariaDB: TẮT"
    fi

    if pgrep -f ServerLogin.jar >/dev/null 2>&1; then
        ok "Login server: ĐANG CHẠY (port 8888)"
    else
        err "Login server: TẮT"
    fi

    if pgrep -f Srcgame.jar >/dev/null 2>&1; then
        ok "Game server: ĐANG CHẠY (port 14445)"
    else
        err "Game server: TẮT"
    fi

    echo ""
    [ -f "$APK_OUT" ] && ok "APK: $APK_OUT ($(du -sh $APK_OUT | cut -f1))" \
                      || warn "APK: chưa có (cần chạy [1] Setup)"

    echo ""
    echo -e "  ${C}── Log game (10 dòng cuối) ──${N}"
    [ -f "$LOG/game.log" ] && tail -10 "$LOG/game.log" || echo "  (chưa có log)"
    echo ""
    read -p "  Nhấn Enter..."
}

do_log() {
    banner
    echo -e "  ${C}════ XEM LOG LIVE ════${N}"
    echo -e "  ${Y}Ctrl+C để thoát${N}"
    echo ""
    [ -f "$LOG/game.log" ] && tail -f "$LOG/game.log" || { warn "Chưa có log game"; read -p "  Enter..."; }
}

# ── ADMIN TOOL ───────────────────────────────────
_db() { mysql -u root hashirama -e "$1" 2>/dev/null; }

admin_give() {
    local col="$1" label="$2"
    echo ""
    read -p "  Tên nhân vật: " cname
    read -p "  Số $label: " amount
    local exist
    exist=$(_db "SELECT COUNT(*) FROM nro_nhan_vat WHERE name='$cname';" | tail -1)
    if [ "$exist" = "0" ] || [ -z "$exist" ]; then
        err "Không tìm thấy '$cname'!"
    else
        _db "UPDATE nro_nhan_vat SET $col=$col+$amount WHERE name='$cname';" && \
            ok "Đã nạp $amount $label cho '$cname'!" || err "Thất bại!"
        _db "SELECT name, level, vang, ngoc FROM nro_nhan_vat WHERE name='$cname';"
    fi
    read -p "  [Enter]..."
}

admin_menu() {
    while true; do
        banner
        echo -e "  ${W}══════ ADMIN TOOL ══════${N}"
        echo ""
        mysqladmin ping -u root --silent 2>/dev/null \
            && echo -e "  ${G}● DB: Online${N}" \
            || echo -e "  ${R}● DB: Offline (chạy [2] Bật server)${N}"
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
        read -r -p "  Chọn: " ch
        case "$ch" in
            1) admin_give "vang" "vàng" ;;
            2) admin_give "ngoc" "ngọc" ;;
            3) admin_give "exp"  "EXP"  ;;
            4)
                echo ""
                _db "SELECT name, level, vang, ngoc, exp FROM nro_nhan_vat ORDER BY level DESC LIMIT 30;"
                read -p "  [Enter]..."
                ;;
            5)
                echo ""
                read -p "  Username: " u
                read -s -p "  Password: " p; echo ""
                local h; h=$(echo -n "$p" | md5sum | cut -d' ' -f1)
                _db "INSERT INTO account (username, password) VALUES ('$u','$h');" && \
                    ok "Tạo tài khoản '$u' OK!" || err "Thất bại (đã tồn tại?)"
                read -p "  [Enter]..."
                ;;
            6)
                echo ""
                read -p "  Username: " u
                read -s -p "  Pass mới: " p; echo ""
                local h; h=$(echo -n "$p" | md5sum | cut -d' ' -f1)
                _db "UPDATE account SET password='$h' WHERE username='$u';" && ok "OK!" || err "Thất bại!"
                read -p "  [Enter]..."
                ;;
            7)
                echo ""
                read -p "  Username: " u
                echo -e "  ${Y}[1]${N} Ban  ${Y}[2]${N} Unban"
                read -r -p "  Chọn: " bc
                [[ "$bc" == "1" ]] && _db "UPDATE account SET status=0 WHERE username='$u';" && ok "Đã ban '$u'" || true
                [[ "$bc" == "2" ]] && _db "UPDATE account SET status=1 WHERE username='$u';" && ok "Đã unban '$u'" || true
                read -p "  [Enter]..."
                ;;
            8)
                echo ""
                _db "SHOW TABLES;"
                echo ""
                read -p "  SQL: " sql
                [[ -n "$sql" ]] && _db "$sql"
                read -p "  [Enter]..."
                ;;
            0) break ;;
        esac
    done
}

do_reset_data() {
    banner
    echo -e "  ${C}════ XOÁ DỮ LIỆU ════${N}"
    echo ""
    warn "Xoá toàn bộ tài khoản và nhân vật?"
    read -p "  Gõ 'yes' để xác nhận: " confirm
    if [ "$confirm" = "yes" ]; then
        mysqladmin ping -u root --silent 2>/dev/null || start_db
        mysql -u root 2>/dev/null <<SQL
DROP DATABASE IF EXISTS hashirama;
CREATE DATABASE hashirama CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON hashirama.* TO 'root'@'localhost';
FLUSH PRIVILEGES;
SQL
        # Import lại SQL
        [ -f "$DIR/nro_hashirama.sql" ] && mysql -u root hashirama < "$DIR/nro_hashirama.sql" 2>/dev/null && ok "DB reset + import lại OK" || ok "DB reset OK"
    else
        warn "Huỷ"
    fi
    read -p "  Nhấn Enter..."
}

# ══════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════
main_menu() {
    while true; do
        banner
        status_bar

        if [ -f "$SETUP_FLAG" ]; then
            echo -e "  ${G}[✓] Đã setup${N}  •  JAR: $([ -f "$GAME_JAR" ] && echo OK || echo THIẾU)  •  APK: $([ -f "$APK_OUT" ] && echo OK || echo THIẾU)"
            echo ""
        fi

        echo -e "  ${W}[1]${N} 📦  Setup / Tải lại files"
        echo -e "  ${W}[2]${N} ▶   Bật server"
        echo -e "  ${W}[3]${N} ■   Tắt server"
        echo -e "  ${W}[4]${N} 📊  Trạng thái"
        echo -e "  ${W}[5]${N} 📜  Xem log live"
        echo -e "  ${W}[6]${N} 👑  Admin tool (vàng/ngọc/ban...)"
        echo -e "  ${W}[7]${N} 🗑   Xoá dữ liệu game"
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
            0) echo ""; exit 0 ;;
            *) warn "Chọn lại" ; sleep 1 ;;
        esac
    done
}

# ── Khởi chạy ────────────────────────────────────
mkdir -p "$DIR/game" "$DIR/login" "$LOG"
main_menu
