#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STATE_DIR="${TELEBOTGEN_STATE_DIR:-/etc/ADM-db}"
REPOSITORY="${TELEBOTGEN_REPOSITORY:-Gh0stDeveloper/TeleBotGen}"
REF="${TELEBOTGEN_REF:-feat/hextunnel-license-integration}"

if [[ -r "$STATE_DIR/repository.env" ]]; then
    # shellcheck disable=SC1091
    source "$STATE_DIR/repository.env"
    REPOSITORY="${TELEBOTGEN_REPOSITORY:-$REPOSITORY}"
    REF="${TELEBOTGEN_REF:-$REF}"
fi
RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/${REF}"

notify_admin() {
    local message="$1" token admin_id config response
    token="$(tr -d '\r\n' < "$STATE_DIR/token" 2>/dev/null || true)"
    admin_id="$(head -n1 "$STATE_DIR/Admin-ID" 2>/dev/null || true)"
    [[ -n "$token" && "$admin_id" =~ ^[0-9]+$ ]] || return 0
    config="$(mktemp /tmp/telebotgen-telegram.XXXXXX)"
    response="$(mktemp /tmp/telebotgen-telegram-response.XXXXXX)"
    {
        printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token"
        printf 'request = "POST"\n'
    } > "$config"
    chmod 600 "$config" "$response"
    curl -sS --max-time 10 --config "$config" \
        --data-urlencode "chat_id=$admin_id" \
        --data-urlencode "text=$message" \
        -o "$response" >/dev/null 2>&1 || true
    rm -f "$config" "$response"
}

[[ "${EUID:-$(id -u)}" -eq 0 ]] || {
    echo 'TeleBotGen update must run as root.' >&2
    exit 1
}

installer="$(mktemp /tmp/telebotgen-deploy.XXXXXX)"
trap 'rm -f "${installer:-}"' EXIT
notify_admin "TeleBotGen: iniciando actualización desde ${REPOSITORY}@${REF}."

curl -fsSL --retry 3 --connect-timeout 8 --max-time 60 \
    "$RAW_BASE/deploy.sh" -o "$installer"
sed -i 's/\r$//' "$installer"
bash -n "$installer"
chmod 700 "$installer"

if TELEBOTGEN_REPOSITORY="$REPOSITORY" TELEBOTGEN_REF="$REF" \
    bash "$installer"; then
    version="$(tr -d '\r\n' < "$STATE_DIR/vercion" 2>/dev/null || printf desconocida)"
    notify_admin "TeleBotGen actualizado correctamente a ${version}."
else
    notify_admin 'TeleBotGen: actualización revertida. Revisa journalctl -u telebotgen.'
    exit 1
fi
