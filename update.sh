#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STATE_DIR="${TELEBOTGEN_STATE_DIR:-/etc/ADM-db}"
DEPLOY_ENV="${TELEBOTGEN_DEPLOY_ENV:-/etc/telebotgen/deploy.env}"

[[ "${EUID:-$(id -u)}" -eq 0 ]] || {
    echo 'TeleBotGen update must run as root.' >&2
    exit 1
}
[[ -f "$DEPLOY_ENV" ]] || {
    echo "ERROR: falta la configuración protegida $DEPLOY_ENV." >&2
    exit 1
}
owner="$(stat -c '%U' "$DEPLOY_ENV")"
mode="$(stat -c '%a' "$DEPLOY_ENV")"
[[ "$owner" == root && "$mode" == 600 ]] || {
    echo "ERROR: $DEPLOY_ENV debe pertenecer a root y usar modo 600." >&2
    exit 1
}
# shellcheck disable=SC1090
source "$DEPLOY_ENV"
REPOSITORY="${TELEBOTGEN_REPOSITORY:-}"
REF="${TELEBOTGEN_REF:-}"
[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
    echo 'ERROR: repositorio protegido inválido.' >&2
    exit 1
}
[[ "$REF" =~ ^[A-Za-z0-9._/-]+$ && "$REF" != /* && "$REF" != *..* ]] || {
    echo 'ERROR: referencia protegida inválida.' >&2
    exit 1
}
RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/${REF}"
unset owner mode

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

installer="$(mktemp /tmp/telebotgen-deploy.XXXXXX)"
trap 'rm -f "${installer:-}"' EXIT
notify_admin '🔄 Actualización iniciada.'

curl -fsSL --retry 3 --connect-timeout 8 --max-time 60 \
    "$RAW_BASE/deploy.sh" -o "$installer"
sed -i 's/\r$//' "$installer"
bash -n "$installer"
chmod 700 "$installer"

if TELEBOTGEN_REPOSITORY="$REPOSITORY" TELEBOTGEN_REF="$REF" \
    bash "$installer"; then
    version="$(tr -d '\r\n' < "$STATE_DIR/vercion" 2>/dev/null || printf desconocida)"
    notify_admin "✅ Actualización completada. Versión: ${version}."
else
    notify_admin '❌ La actualización no pudo completarse y se restauró la versión anterior.'
    exit 1
fi
