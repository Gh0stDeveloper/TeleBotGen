#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STATE_DIR="${TELEBOTGEN_STATE_DIR:-/etc/ADM-db}"
REPOSITORY="${TELEBOTGEN_REPOSITORY:-Gh0stDeveloper/TeleBotGen}"
REF="${TELEBOTGEN_REF:-main}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DURATION_FILE="$STATE_DIR/Key-Duration-Minutes"
BAR='============================================================'

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'ERROR: ejecuta como root.' >&2; exit 1; }; }
pause_menu() { read -r -p 'Presiona Enter para continuar...' _; }
valid_duration() { [[ "${1:-}" =~ ^[0-9]+$ && "$1" -ge 1 && "$1" -le 525600 ]]; }

prepare_state() {
    local duration
    install -d -m 700 "$STATE_DIR" "$STATE_DIR/sources"
    for file in Admin-ID Reseller-ID Allowed-Groups; do
        [[ -e "$STATE_DIR/$file" ]] || : > "$STATE_DIR/$file"
        chmod 600 "$STATE_DIR/$file"
    done
    duration="$(tr -d '[:space:]' < "$DURATION_FILE" 2>/dev/null || true)"
    valid_duration "$duration" || printf '240\n' > "$DURATION_FILE"
    chmod 600 "$DURATION_FILE"
}

deploy_bot() {
    local deployer=""
    if [[ -x /usr/local/bin/telebotgen-deploy ]]; then
        deployer=/usr/local/bin/telebotgen-deploy
        TELEBOTGEN_REPOSITORY="$REPOSITORY" TELEBOTGEN_REF="$REF" bash "$deployer"
    elif [[ -f "$SCRIPT_DIR/deploy.sh" ]]; then
        TELEBOTGEN_SOURCE_ROOT="$SCRIPT_DIR" \
        TELEBOTGEN_REPOSITORY="$REPOSITORY" TELEBOTGEN_REF="$REF" \
            bash "$SCRIPT_DIR/deploy.sh"
    else
        deployer="$(mktemp /tmp/telebotgen-deploy.XXXXXX)"
        curl -fsSL --retry 3 --connect-timeout 8 --max-time 60 \
            "https://raw.githubusercontent.com/${REPOSITORY}/${REF}/deploy.sh" -o "$deployer"
        bash -n "$deployer"
        TELEBOTGEN_REPOSITORY="$REPOSITORY" TELEBOTGEN_REF="$REF" bash "$deployer"
        rm -f "$deployer"
    fi
}

configure_token() {
    local token
    read -r -s -p 'Token de @BotFather: ' token
    printf '\n'
    [[ "$token" =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{30,}$ ]] || { echo 'Token inválido.'; return 1; }
    printf '%s\n' "$token" > "$STATE_DIR/token"
    chmod 600 "$STATE_DIR/token"
}

configure_admin() {
    local value
    read -r -p 'ID numérico del administrador: ' value
    [[ "$value" =~ ^[0-9]+$ ]] || { echo 'ID inválido.'; return 1; }
    printf '%s\n' "$value" > "$STATE_DIR/Admin-ID"
    chmod 600 "$STATE_DIR/Admin-ID"
}

configure_duration() {
    local value
    read -r -p 'Duración de nuevas keys en minutos: ' value
    valid_duration "$value" || { echo 'Usa un valor entre 1 y 525600.'; return 1; }
    printf '%s\n' "$value" > "$DURATION_FILE"
    chmod 600 "$DURATION_FILE"
}

append_numeric() {
    local file="$1" prompt="$2" value
    read -r -p "$prompt: " value
    [[ "$value" =~ ^[0-9]+$ ]] || { echo 'ID inválido.'; return 1; }
    grep -Fxq "$value" "$file" 2>/dev/null || printf '%s\n' "$value" >> "$file"
    sort -u -o "$file" "$file"
    chmod 600 "$file"
}

append_group() {
    local value
    read -r -p 'ID negativo del grupo: ' value
    [[ "$value" =~ ^-[0-9]+$ ]] || { echo 'ID de grupo inválido.'; return 1; }
    grep -Fxq -- "$value" "$STATE_DIR/Allowed-Groups" 2>/dev/null \
        || printf '%s\n' "$value" >> "$STATE_DIR/Allowed-Groups"
    sort -u -o "$STATE_DIR/Allowed-Groups" "$STATE_DIR/Allowed-Groups"
    chmod 600 "$STATE_DIR/Allowed-Groups"
}

send_test() {
    local token admin_id config response
    token="$(tr -d '\r\n' < "$STATE_DIR/token" 2>/dev/null || true)"
    admin_id="$(head -n1 "$STATE_DIR/Admin-ID" 2>/dev/null || true)"
    [[ -n "$token" && "$admin_id" =~ ^[0-9]+$ ]] || { echo 'Configura token y administrador.'; return 1; }
    config="$(mktemp /tmp/telebotgen-test.XXXXXX)"
    response="$(mktemp /tmp/telebotgen-test-response.XXXXXX)"
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\nrequest = "POST"\n' "$token" > "$config"
    chmod 600 "$config" "$response"
    curl -sS --max-time 10 --config "$config" \
        --data-urlencode "chat_id=$admin_id" \
        --data-urlencode 'text=TeleBotGen y GhostDeveloperLicenseServer están operativos.' \
        -o "$response"
    if jq -e '.ok == true' "$response" >/dev/null; then
        echo 'Mensaje enviado.'
    else
        jq -r '.description // "Telegram rechazó el mensaje."' "$response"
        rm -f "$config" "$response"
        return 1
    fi
    rm -f "$config" "$response"
}

show_status() {
    local version duration
    version="$(tr -d '\r\n' < "$STATE_DIR/vercion" 2>/dev/null || printf no-instalada)"
    duration="$(tr -d '[:space:]' < "$DURATION_FILE" 2>/dev/null || printf 240)"
    printf '%s\nESTADO TELEBOTGEN\n%s\n' "$BAR" "$BAR"
    printf 'Versión: %s\n' "$version"
    printf 'Servicio: %s\n' "$(systemctl is-active telebotgen.service 2>/dev/null || true)"
    printf 'API: '
    curl -fsS --connect-timeout 3 --max-time 8 http://127.0.0.1:8080/health \
        | jq -r '.status + " " + .version' || echo OFFLINE
    printf 'Duración: %s minutos\n' "$duration"
    printf 'Legacy 8888: '
    ss -lntp 2>/dev/null | grep -q ':8888 ' && echo 'ERROR: activo' || echo desactivado
    printf '\nGrupos permitidos:\n'
    cat "$STATE_DIR/Allowed-Groups" 2>/dev/null || true
    printf '\nÚltimos logs:\n'
    journalctl -u telebotgen.service -n 20 --no-pager 2>/dev/null || true
}

interactive_menu() {
    local option
    while true; do
        clear || true
        printf '%s\n TELEBOTGEN / HEX TUNNEL\n%s\n' "$BAR" "$BAR"
        cat <<'EOF'
 [1] Configurar token
 [2] Configurar administrador
 [3] Agregar revendedor
 [4] Agregar grupo permitido
 [5] Configurar duración de keys
 [6] Instalar/actualizar transaccionalmente
 [7] Iniciar/detener bot
 [8] Enviar mensaje de prueba
 [9] Estado y diagnósticos
 [0] Salir
EOF
        printf '%s\n' "$BAR"
        read -r -p 'Opción: ' option
        case "$option" in
            1) configure_token || true ;;
            2) configure_admin || true ;;
            3) append_numeric "$STATE_DIR/Reseller-ID" 'ID del revendedor' || true ;;
            4) append_group || true ;;
            5) configure_duration || true ;;
            6) deploy_bot ;;
            7)
                if systemctl is-active --quiet telebotgen.service; then
                    systemctl stop telebotgen.service
                else
                    systemctl start telebotgen.service
                fi
                ;;
            8) send_test || true ;;
            9) show_status ;;
            0) return ;;
            *) echo 'Opción inválida.' ;;
        esac
        pause_menu
    done
}

main() {
    require_root
    prepare_state
    case "${1:-menu}" in
        install|update|deploy) deploy_bot ;;
        status) show_status ;;
        menu) interactive_menu ;;
        *) echo 'Uso: confbot.sh [install|update|status|menu]' >&2; exit 2 ;;
    esac
}

main "$@"
