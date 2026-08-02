#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export TELEBOTGEN_ADMIN_FILE="$TMP/Admin-ID"
export TELEBOTGEN_RESELLER_FILE="$TMP/Reseller-ID"
export TELEBOTGEN_GROUP_FILE="$TMP/Allowed-Groups"
export TELEBOTGEN_KEY_DURATION_FILE="$TMP/Key-Duration-Minutes"
export TELEBOTGEN_LICENSE_ADMIN_TOKEN_FILE="$TMP/admin-token"
printf 'test-token\n' > "$TELEBOTGEN_LICENSE_ADMIN_TOKEN_FILE"
chmod 600 "$TELEBOTGEN_LICENSE_ADMIN_TOKEN_FILE"

# shellcheck source=/dev/null
source "$ROOT/sources/license_api"
# shellcheck source=/dev/null
source "$ROOT/sources/roles"
# shellcheck source=/dev/null
source "$ROOT/sources/gerar_key"
roles_prepare_files

printf '100\n' > "$TELEBOTGEN_ADMIN_FILE"
printf '200\n' > "$TELEBOTGEN_RESELLER_FILE"
printf '%s\n' '-1001234567890' > "$TELEBOTGEN_GROUP_FILE"

role_is_admin 100
! role_is_admin 200
role_is_reseller 200
group_is_allowed -1001234567890
! group_is_allowed -100999
keygen_context_allowed private 400
keygen_context_allowed group -1001234567890
! keygen_context_allowed group -100999

[[ "$(key_duration_get)" == 240 ]]
key_duration_set 1440
[[ "$(key_duration_get)" == 1440 ]]
valid_key_duration 1
valid_key_duration 525600
! valid_key_duration 0
! valid_key_duration 525601
! valid_key_duration texto

# La resolución de rol debe consultar por dueño en el servidor, no descargar
# las últimas 200 licencias globales.
license_api_request() {
    local method="$1" path="$2"
    [[ "$method" == GET ]]
    printf '%s\n' "$path" >> "$TMP/api-paths"
    case "$path" in
        *owner_telegram_id=300*active_only=true*)
            cat <<'JSON'
{"items":[{"id":"active","key_prefix":"HT-ACTIVE","product":"hextunnel","owner_telegram_id":"300","owner_username":"client","status":"active","created_at":"2026-01-01T00:00:00Z","expires_at":"2099-01-01T00:00:00Z","activation_limit":1,"activation_count":0,"bound_ip":null,"activated_at":null,"revoked_at":null,"revoke_reason":null,"metadata":{}}],"total":1,"limit":1,"offset":0}
JSON
            ;;
        *owner_telegram_id=300*)
            cat <<'JSON'
{"items":[{"id":"active","key_prefix":"HT-ACTIVE","product":"hextunnel","owner_telegram_id":"300","owner_username":"client","status":"active","created_at":"2026-01-01T00:00:00Z","expires_at":"2099-01-01T00:00:00Z","activation_limit":1,"activation_count":0,"bound_ip":null,"activated_at":null,"revoked_at":null,"revoke_reason":null,"metadata":{}},{"id":"old","key_prefix":"HT-OLD","product":"hextunnel","owner_telegram_id":"300","owner_username":"client","status":"expired","created_at":"2025-01-01T00:00:00Z","expires_at":"2025-01-02T00:00:00Z","activation_limit":1,"activation_count":1,"bound_ip":null,"activated_at":null,"revoked_at":null,"revoke_reason":null,"metadata":{}}],"total":2,"limit":200,"offset":0}
JSON
            ;;
        *)
            printf '{"items":[],"total":0,"limit":1,"offset":0}\n'
            ;;
    esac
}

actor_resolve_role 100
[[ "$actor_role" == admin ]]
actor_resolve_role 200
[[ "$actor_role" == reseller ]]
actor_resolve_role 300
[[ "$actor_role" == client ]]
[[ "$(jq -r .id <<< "$actor_license_json")" == active ]]
actor_resolve_role 400
[[ "$actor_role" == public ]]
grep -Fq 'owner_telegram_id=300&active_only=true&limit=1' "$TMP/api-paths"
! grep -Fq '/api/v1/admin/licenses?product=hextunnel&limit=200&offset=0' "$TMP/api-paths"

[[ "$(license_human_duration 90060)" == '1 día(s), 1 hora(s) y 1 minuto(s)' ]]
command_text="$(hextunnel_install_command)"
grep -Fq 'command -v curl' <<< "$command_text"
grep -Fq 'https://ghostdeveloper.duckdns.org/install.sh' <<< "$command_text"
[[ "$(hextunnel_upgrade_command)" == 'sudo hextunnel-upgrade' ]]

# Flujo real de /Keygen dentro de un grupo permitido: el dueño siempre es el remitente.
license_api_active_for_owner() { return 0; }
license_api_create() {
    printf '%s\n' "$@" > "$TMP/create-args"
    cat <<'JSON'
{"id":"11111111-2222-3333-4444-555555555555","key":"HT-SELF-SERVICE-TEST","expires_at":"2099-01-01T00:00:00Z"}
JSON
}
license_api_revoke() { printf '%s\n' "$@" > "$TMP/revoke-args"; }
send_html() {
    local chat_id="$1" text="$2"
    printf '%s|%s\n' "$chat_id" "$text" >> "$TMP/messages"
}
msj_fun() { printf '%b' "$bot_retorno" > "$TMP/private-message"; }

LINE='============================'
current_chat_type='group'
current_chat_id='-1001234567890'
actor_id='400'
actor_username='alice_test'
actor_role='public'
comando=(/Keygen)
key_duration_set 60
rm -f "$TMP/create-args" "$TMP/messages"
gerar_key

mapfile -t create_args < "$TMP/create-args"
[[ "${create_args[0]}" == 60 ]]
[[ "${create_args[1]}" == 400 ]]
[[ "${create_args[2]}" == alice_test ]]
[[ "${create_args[3]}" == 400 ]]
[[ "${create_args[4]}" == allowed-group-member ]]
[[ "${create_args[5]}" == -1001234567890 ]]
grep -Fq '400|<b>HEX TUNNEL — TU LICENCIA</b>' "$TMP/messages"
grep -Fq 'HT-SELF-SERVICE-TEST' "$TMP/messages"
grep -Fq -- '-1001234567890|<b>Key generada.</b>' "$TMP/messages"

# El usuario no puede enviar ID, usuario ni duración manualmente.
rm -f "$TMP/create-args" "$TMP/private-message"
current_chat_type='private'
current_chat_id='400'
comando=(/Keygen 999 123456 usuario)
gerar_key
[[ ! -e "$TMP/create-args" ]]
grep -Fq 'Usa solamente <code>/Keygen</code>' "$TMP/private-message"

# Una cuenta con licencia activa no puede generar una segunda key.
license_api_active_for_owner() {
    cat <<'JSON'
{"id":"existing-license","status":"active","expires_at":"2099-01-01T00:00:00Z","bound_ip":null}
JSON
}
rm -f "$TMP/create-args" "$TMP/private-message"
comando=(/Keygen)
gerar_key
[[ ! -e "$TMP/create-args" ]]
grep -Fq 'Ya tienes una licencia activa' "$TMP/private-message"

echo 'Role, group and self-service license flow tests passed.'
