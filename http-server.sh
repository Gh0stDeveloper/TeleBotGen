#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

KEY_ROOT="${HEXGEN_KEY_ROOT:-/etc/http-shell}"
STATE_ROOT="${HEXGEN_STATE_ROOT:-/etc/ADM-db}"
PORT="${HEXGEN_PORT:-8888}"
BIND_ADDRESS="${HEXGEN_BIND_ADDRESS:-0.0.0.0}"
PROGRAM="${HEXGEN_SERVER_PROGRAM:-/usr/local/bin/hexgen-http-server}"
LOG_FILE="${HEXGEN_LOG_FILE:-/var/log/telebotgen-license.log}"

mkdir -p "$KEY_ROOT" "$STATE_ROOT"
chmod 700 "$KEY_ROOT" "$STATE_ROOT"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

http_response() {
    local status="$1" body="$2" length
    length="$(printf '%s' "$body" | wc -c)"
    printf 'HTTP/1.1 %s\r\n' "$status"
    printf 'Date: %s\r\n' "$(LC_ALL=C date -R)"
    printf 'Server: TeleBotGen\r\n'
    printf 'Content-Type: text/plain; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n'
    printf 'Connection: close\r\n'
    printf 'Content-Length: %s\r\n\r\n' "$length"
    printf '%s' "$body"
}

metadata_value() {
    local file="$1" name="$2" line
    line="$(grep -m1 "^${name}=" "$file" 2>/dev/null || true)"
    printf '%s' "${line#*=}"
}

key_is_expired() {
    local metadata="$1" expires epoch
    expires="$(metadata_value "$metadata" HEXGEN_EXPIRES_AT)"
    [[ -n "$expires" ]] || return 0
    epoch="$(date -d "$expires" +%s 2>/dev/null || printf 0)"
    ((epoch <= $(date -u +%s)))
}

notify_activation() {
    local owner_id="$1" key_display="$2" client_ip="$3" peer_ip="$4" used_at="$5"
    local token admin_id notify_id url message
    token="$(tr -d '\r\n' < "$STATE_ROOT/token" 2>/dev/null || true)"
    admin_id="$(tr -d '\r\n' < "$STATE_ROOT/Admin-ID" 2>/dev/null || true)"
    notify_id="$owner_id"
    [[ "$notify_id" =~ ^[0-9]+$ ]] || notify_id="$admin_id"
    [[ -n "$token" && "$token" != null && "$notify_id" =~ ^[0-9]+$ ]] || return 0

    url="https://api.telegram.org/bot${token}/sendMessage"
    message="HEX TUNNEL — KEY ACTIVADA

Key: ${key_display}
IP declarada: ${client_ip}
IP de conexión: ${peer_ip:-desconocida}
Fecha UTC: ${used_at}"
    curl -fsS --max-time 10 -X POST "$url" \
        --data-urlencode "chat_id=$notify_id" \
        --data-urlencode "text=$message" >/dev/null 2>&1 || true
}

handle_request() {
    local method target protocol header path token resource client_ip extra
    local key_dir consume_dir metadata fixed_ip owner_id peer_ip used_at key_display

    IFS=' ' read -r method target protocol || {
        http_response '400 Bad Request' 'BAD REQUEST'
        return 0
    }
    while IFS= read -r header; do
        header="${header%$'\r'}"
        [[ -z "$header" ]] && break
    done

    [[ "$method" == GET ]] || {
        http_response '405 Method Not Allowed' 'METHOD NOT ALLOWED'
        return 0
    }
    path="${target%%\?*}"
    path="${path#/}"
    IFS='/' read -r token resource client_ip extra <<< "$path"
    [[ -z "$extra" && "$token" =~ ^[0-9a-f]{40}$ && "$resource" == HexGen ]] || {
        http_response '200 OK' 'KEY INVALIDA!'
        return 0
    }
    [[ "$client_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || {
        http_response '200 OK' 'KEY INVALIDA!'
        return 0
    }

    key_dir="$KEY_ROOT/$token"
    metadata="$key_dir/metadata.env"
    [[ -f "$key_dir/HexGen" && -f "$metadata" ]] || {
        http_response '200 OK' 'KEY INVALIDA!'
        return 0
    }
    [[ "$(metadata_value "$metadata" HEXGEN_PRODUCT)" == hextunnel ]] || {
        http_response '200 OK' 'KEY DE GENERADOR!'
        return 0
    }
    if key_is_expired "$metadata"; then
        rm -rf -- "$key_dir" "$KEY_ROOT/$token.name"
        http_response '200 OK' 'KEY INVALIDA!'
        return 0
    fi
    if [[ -s "$key_dir/keyfixa" ]]; then
        fixed_ip="$(tr -d '\r\n' < "$key_dir/keyfixa")"
        [[ "$fixed_ip" == "$client_ip" ]] || {
            http_response '200 OK' 'KEY INVALIDA!'
            return 0
        }
    fi

    consume_dir="$KEY_ROOT/.consuming-${token}-$$"
    if ! mv -- "$key_dir" "$consume_dir" 2>/dev/null; then
        http_response '200 OK' 'KEY INVALIDA!'
        return 0
    fi
    trap 'rm -rf -- "${consume_dir:-}"' EXIT

    owner_id="$(metadata_value "$consume_dir/metadata.env" HEXGEN_OWNER_ID)"
    owner_id="${owner_id//\\/}"
    peer_ip="${SOCAT_PEERADDR:-}"
    used_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    key_display="HexGen/${token:0:8}...${token: -6}"

    printf '%s | %s | %s | %s | %s\n' \
        "$owner_id" "$client_ip" "$peer_ip" "$token" "$used_at" >> "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    rm -f -- "$KEY_ROOT/$token.name"

    http_response '200 OK' 'HexGen'
    notify_activation "$owner_id" "$key_display" "$client_ip" "$peer_ip" "$used_at" &
    rm -rf -- "$consume_dir"
    trap - EXIT
}

serve() {
    command -v socat >/dev/null 2>&1 || die 'socat no está instalado.'
    [[ "$PORT" =~ ^[0-9]{1,5}$ ]] || die 'HEXGEN_PORT es inválido.'
    exec socat \
        "TCP-LISTEN:${PORT},bind=${BIND_ADDRESS},fork,reuseaddr,linger=0" \
        "EXEC:${PROGRAM} --handle,stderr"
}

install_dependencies() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends socat curl ca-certificates coreutils
}

case "${1:---handle}" in
    --serve|-start|-Start|-s|-S|-iniciar|-Iniciar) serve ;;
    --handle) handle_request ;;
    --install|-install|-Install|-i|-I|-instalar|-Instalar) install_dependencies ;;
    *) die "opción desconocida: $1" ;;
esac
