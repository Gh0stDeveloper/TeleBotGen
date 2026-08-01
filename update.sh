#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STATE_DIR="${TELEBOTGEN_STATE_DIR:-/etc/ADM-db}"
REPOSITORY="${TELEBOTGEN_REPOSITORY:-Gh0stDeveloper/TeleBotGen}"
REF="${TELEBOTGEN_REF:-main}"

if [[ -r "$STATE_DIR/repository.env" ]]; then
    # shellcheck disable=SC1091
    source "$STATE_DIR/repository.env"
    REPOSITORY="${TELEBOTGEN_REPOSITORY:-$REPOSITORY}"
    REF="${TELEBOTGEN_REF:-$REF}"
fi
RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/${REF}"

notify_admin() {
    local message="$1" token admin_id
    token="$(tr -d '\r\n' < "$STATE_DIR/token" 2>/dev/null || true)"
    admin_id="$(head -n1 "$STATE_DIR/Admin-ID" 2>/dev/null || true)"
    [[ -n "$token" && "$admin_id" =~ ^[0-9]+$ ]] || return 0
    curl -fsS --max-time 10 -X POST \
        "https://api.telegram.org/bot${token}/sendMessage" \
        --data-urlencode "chat_id=$admin_id" \
        --data-urlencode "text=$message" >/dev/null 2>&1 || true
}

[[ "${EUID:-$(id -u)}" -eq 0 ]] || {
    echo 'TeleBotGen update must run as root.' >&2
    exit 1
}

tmp="$(mktemp /tmp/telebotgen-conf.XXXXXX)"
trap 'rm -f "${tmp:-}"' EXIT
notify_admin 'TeleBotGen: iniciando actualización mediante GhostDeveloperLicenseServer.'

curl -fsSL --retry 3 --connect-timeout 8 --max-time 60 "$RAW_BASE/confbot.sh" -o "$tmp"
sed -i 's/\r$//' "$tmp"
bash -n "$tmp"

# Elimina únicamente la invocación interactiva final; conserva las funciones.
sed -i '/^require_root$/,$d' "$tmp"
# shellcheck source=/dev/null
source "$tmp"

if install_bot_files; then
    systemctl restart telebotgen.service
    notify_admin "TeleBotGen actualizado desde ${REPOSITORY}@${REF}."
else
    notify_admin 'TeleBotGen: la actualización falló; revisa journalctl -u telebotgen.'
    exit 1
fi
