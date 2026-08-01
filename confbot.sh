#!/usr/bin/env bash
# Instalación y configuración de TeleBotGen para GhostDeveloperLicenseServer.
set -Eeuo pipefail
umask 077

CIDdir="${TELEBOTGEN_STATE_DIR:-/etc/ADM-db}"
SRC="$CIDdir/sources"
REPOSITORY="${TELEBOTGEN_REPOSITORY:-Gh0stDeveloper/TeleBotGen}"
REF="${TELEBOTGEN_REF:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/${REF}"
BAR='============================================================'
LICENSE_API='http://127.0.0.1:8080/health'
LICENSE_TOKEN_FILE='/etc/ghostdeveloper-license/secrets/admin-token'

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo 'ERROR: ejecuta como root.' >&2; exit 1; }
}

pause_menu() { read -r -p 'Presiona Enter para continuar...' _; }

install_dependencies() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends bash curl ca-certificates jq openssl coreutils iproute2
}

prepare_state() {
    install -d -m 700 "$CIDdir" "$SRC"
    for file in Admin-ID Reseller-ID Allowed-Groups; do
        [[ -e "$CIDdir/$file" ]] || : > "$CIDdir/$file"
        chmod 600 "$CIDdir/$file"
    done
    cat > "$CIDdir/repository.env" <<EOF
TELEBOTGEN_REPOSITORY=$(printf '%q' "$REPOSITORY")
TELEBOTGEN_REF=$(printf '%q' "$REF")
EOF
    chmod 600 "$CIDdir/repository.env"
}

verify_license_api() {
    [[ -s "$LICENSE_TOKEN_FILE" ]] || {
        echo "ERROR: no existe $LICENSE_TOKEN_FILE. Instala primero GhostDeveloperLicenseServer." >&2
        return 1
    }
    curl -fsS --connect-timeout 3 --max-time 8 "$LICENSE_API" | jq -e '.status == "online"' >/dev/null || {
        echo 'ERROR: la API local de licencias no está operativa.' >&2
        return 1
    }
}

download_file() {
    local url="$1" destination="$2" mode="${3:-700}" tmp
    tmp="$(mktemp /tmp/telebotgen-file.XXXXXX)"
    curl -fsSL --retry 3 --connect-timeout 8 --max-time 60 "$url" -o "$tmp"
    [[ -s "$tmp" ]] || { rm -f "$tmp"; return 1; }
    sed -i 's/\r$//' "$tmp"
    install -m "$mode" "$tmp" "$destination"
    rm -f "$tmp"
}

remove_legacy_validator() {
    systemctl disable --now hexgen-http.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/hexgen-http.service /usr/local/bin/hexgen-http-server
    systemctl daemon-reload
}

create_service() {
    cat > /etc/systemd/system/telebotgen.service <<'EOF'
[Unit]
Description=TeleBotGen - administración de licencias Hex Tunnel
After=network-online.target ghost-license-api.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/bash /etc/ADM-db/BotGen.sh
Restart=on-failure
RestartSec=5s
User=root
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
LockPersonality=true
RestrictSUIDSGID=true
ReadOnlyPaths=/opt/ghostdeveloper-license-server /etc/ghostdeveloper-license
ReadWritePaths=/etc/ADM-db

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable telebotgen.service >/dev/null
}

install_bot_files() {
    local staging list item destination
    require_root
    install_dependencies
    prepare_state
    verify_license_api
    systemctl stop telebotgen.service >/dev/null 2>&1 || true
    remove_legacy_validator

    staging="$(mktemp -d /tmp/telebotgen-update.XXXXXX)"
    list="$staging/lista-bot"
    download_file "$RAW_BASE/sources/lista-bot" "$list" 600

    while IFS= read -r item; do
        [[ -n "$item" && "$item" =~ ^[A-Za-z0-9._-]+$ ]] || continue
        download_file "$RAW_BASE/sources/$item" "$staging/$item" 700
    done < "$list"

    find "$SRC" -mindepth 1 -maxdepth 1 -type f -delete
    for item in "$staging"/*; do
        [[ "${item##*/}" == lista-bot ]] && continue
        if [[ "${item##*/}" == BotGen.sh ]]; then
            destination="$CIDdir/BotGen.sh"
        else
            destination="$SRC/${item##*/}"
        fi
        install -m 700 "$item" "$destination"
    done

    download_file "$RAW_BASE/ShellBot.sh" /bin/ShellBot.sh 700
    download_file "$RAW_BASE/update.sh" /usr/local/bin/telebotgen-update 700
    curl -fsSL --retry 2 "$RAW_BASE/Vercion" -o "$CIDdir/vercion" || printf 'desarrollo\n' > "$CIDdir/vercion"
    chmod 600 "$CIDdir/vercion"
    create_service

    if [[ -s "$CIDdir/token" && -s "$CIDdir/Admin-ID" ]]; then
        systemctl restart telebotgen.service
    fi
    rm -rf "$staging"
    echo 'TeleBotGen instalado y conectado a GhostDeveloperLicenseServer.'
}

configure_token() {
    local token
    read -r -s -p 'Token de @BotFather: ' token; printf '\n'
    [[ "$token" =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{30,}$ ]] || { echo 'Token inválido.'; pause_menu; return; }
    printf '%s\n' "$token" > "$CIDdir/token"; chmod 600 "$CIDdir/token"
    echo 'Token guardado.'; pause_menu
}

configure_admin() {
    local value
    read -r -p 'ID numérico del administrador: ' value
    [[ "$value" =~ ^[0-9]+$ ]] || { echo 'ID inválido.'; pause_menu; return; }
    printf '%s\n' "$value" > "$CIDdir/Admin-ID"; chmod 600 "$CIDdir/Admin-ID"
    echo 'Administrador guardado.'; pause_menu
}

append_numeric() {
    local file="$1" label="$2" value
    read -r -p "$label: " value
    [[ "$value" =~ ^[0-9]+$ ]] || { echo 'ID inválido.'; pause_menu; return; }
    grep -Fxq "$value" "$file" 2>/dev/null || printf '%s\n' "$value" >> "$file"
    sort -u -o "$file" "$file"; chmod 600 "$file"
    echo 'Guardado.'; pause_menu
}

append_group() {
    local value
    read -r -p 'ID negativo del grupo (-100...): ' value
    [[ "$value" =~ ^-[0-9]+$ ]] || { echo 'ID de grupo inválido.'; pause_menu; return; }
    grep -Fxq -- "$value" "$CIDdir/Allowed-Groups" 2>/dev/null || printf '%s\n' "$value" >> "$CIDdir/Allowed-Groups"
    sort -u -o "$CIDdir/Allowed-Groups" "$CIDdir/Allowed-Groups"; chmod 600 "$CIDdir/Allowed-Groups"
    echo 'Grupo permitido.'; pause_menu
}

toggle_bot() {
    if systemctl is-active --quiet telebotgen.service; then systemctl stop telebotgen.service; else verify_license_api && systemctl start telebotgen.service; fi
    systemctl is-active telebotgen.service || true
    pause_menu
}

send_test_message() {
    local token admin_id response
    token="$(tr -d '\r\n' < "$CIDdir/token" 2>/dev/null || true)"
    admin_id="$(head -n1 "$CIDdir/Admin-ID" 2>/dev/null || true)"
    [[ -n "$token" && "$admin_id" =~ ^[0-9]+$ ]] || { echo 'Configura token y administrador.'; pause_menu; return; }
    response="$(curl -fsS --max-time 10 -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        --data-urlencode "chat_id=$admin_id" \
        --data-urlencode 'text=TeleBotGen y GhostDeveloperLicenseServer están conectados.' 2>/dev/null || true)"
    grep -q '"ok":true' <<< "$response" && echo 'Mensaje enviado.' || echo 'Telegram rechazó el mensaje.'
    pause_menu
}

show_status() {
    clear
    printf '%s\nESTADO TELEBOTGEN\n%s\n' "$BAR" "$BAR"
    printf 'API local: '; curl -fsS "$LICENSE_API" 2>/dev/null | jq -r '.status + " " + .version' || echo OFFLINE
    printf 'Bot: '; systemctl is-active telebotgen.service || true
    printf 'Legacy 8888: '; ss -lntp 2>/dev/null | grep -q ':8888 ' && echo 'ERROR: activo' || echo 'desactivado'
    printf '\nRevendedores:\n'; cat "$CIDdir/Reseller-ID" 2>/dev/null || true
    printf '\nGrupos permitidos:\n'; cat "$CIDdir/Allowed-Groups" 2>/dev/null || true
    printf '\nÚltimos logs:\n'; journalctl -u telebotgen.service -n 20 --no-pager 2>/dev/null || true
    pause_menu
}

bot_gen() {
    local option bot_state version
    while true; do
        clear
        systemctl is-active --quiet telebotgen.service && bot_state='ONLINE' || bot_state='OFFLINE'
        version="$(cat "$CIDdir/vercion" 2>/dev/null || printf desarrollo)"
        printf '%s\n TELEBOTGEN / HEX TUNNEL %s\n%s\n' "$BAR" "$version" "$BAR"
        printf '[1] Configurar token de Telegram\n'
        printf '[2] Configurar administrador\n'
        printf '[3] Agregar revendedor\n'
        printf '[4] Agregar grupo permitido\n'
        printf '[5] Instalar/actualizar archivos\n'
        printf '[6] Iniciar/detener bot             %s\n' "$bot_state"
        printf '[7] Enviar mensaje de prueba\n'
        printf '[8] Estado y diagnósticos\n'
        printf '[0] Salir\n%s\n' "$BAR"
        read -r -p 'Opción: ' option
        case "$option" in
            1) configure_token ;;
            2) configure_admin ;;
            3) append_numeric "$CIDdir/Reseller-ID" 'ID del revendedor' ;;
            4) append_group ;;
            5) install_bot_files; pause_menu ;;
            6) toggle_bot ;;
            7) send_test_message ;;
            8) show_status ;;
            0) return ;;
            *) echo 'Opción inválida.'; sleep 1 ;;
        esac
    done
}

require_root
install_dependencies
prepare_state
if [[ ! -s "$CIDdir/BotGen.sh" ]]; then install_bot_files; else remove_legacy_validator; create_service; fi
bot_gen
