#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export TELEBOTGEN_STATE_DIR="$TMP/state"
export TELEBOTGEN_ADMIN_FILE="$TMP/state/Admin-ID"
export TELEBOTGEN_RESELLER_FILE="$TMP/state/Reseller-ID"
export TELEBOTGEN_CLIENT_FILE="$TMP/state/Client-ID"
export TELEBOTGEN_GROUP_FILE="$TMP/state/Allowed-Groups"
export TELEBOTGEN_GROUP_OWNER_FILE="$TMP/state/Group-Owners.tsv"
export TELEBOTGEN_RESELLER_NAME_FILE="$TMP/state/Reseller-Names.tsv"
export TELEBOTGEN_ISSUED_KEY_FILE="$TMP/state/Issued-Keys.tsv"
export TELEBOTGEN_KEY_DURATION_FILE="$TMP/state/Key-Duration-Minutes"
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
printf '300\n' > "$TELEBOTGEN_CLIENT_FILE"
printf '%s\n' '-1001234567890' > "$TELEBOTGEN_GROUP_FILE"
group_owner_set -1001234567890 200
reseller_name_set 200 'Reseller Norte'
reseller_name_set 300 'Cliente Store'

role_is_admin 100
role_is_reseller 200
role_is_client 300
! role_is_client 400
actor_resolve_role 100; [[ "$actor_role" == admin ]]
actor_resolve_role 200; [[ "$actor_role" == reseller ]]
actor_resolve_role 300; [[ "$actor_role" == client ]]
actor_resolve_role 400; [[ "$actor_role" == public ]]

keygen_context_allowed private 300 client
! keygen_context_allowed private 400 public
keygen_context_allowed group -1001234567890 public
! keygen_context_allowed group -100999 public
[[ "$(group_owner_get -1001234567890)" == 200 ]]
[[ "$(group_reseller_name_get -1001234567890)" == 'Reseller Norte' ]]
[[ "$(reseller_name_get 400)" == 'Hex Tunnel Bot Gen' ]]
! reseller_name_set 300 '<nombre inválido>'

[[ "$(key_duration_get)" == 240 ]]
key_duration_set 1440
[[ "$(key_duration_get)" == 1440 ]]

issued_key_store license-1 'HT-FULL-KEY-ONE'
[[ "$(issued_key_get license-1)" == 'HT-FULL-KEY-ONE' ]]
issued_key_remove license-1
[[ -z "$(issued_key_get license-1)" ]]

license_api_create() {
    printf '%s\n' "$@" > "$TMP/create-args"
    cat <<'JSON'
{"id":"11111111-2222-3333-4444-555555555555","key":"HT-TRANSFERABLE-TEST","expires_at":"2099-01-01T00:00:00Z"}
JSON
}
license_api_create_installer_link() {
    printf '%s\n' "$@" > "$TMP/link-args"
    cat <<'JSON'
{"url":"https://ghostdeveloperkeys.duckdns.org/i/temp-test","expires_at":"2099-01-01T00:15:00Z"}
JSON
}
license_api_revoke() { printf '%s\n' "$@" > "$TMP/revoke-args"; }
send_html() { printf '%s|%s\n' "$1" "$2" >> "$TMP/messages"; }
msj_fun() { printf '%b' "$bot_retorno" > "$TMP/current-message"; }
LINE='━━━━━━━━━━━━━━━━━━━━'

# Un miembro sin rol puede generar dentro de un grupo permitido. El reseller
# procede del revendedor que autorizó ese grupo y la entrega ocurre en el grupo.
current_chat_type='group'
current_chat_id='-1001234567890'
actor_id='400'
actor_username='alice_test'
actor_role='public'
comando=(/Keygen)
key_duration_set 60
gerar_key

mapfile -t create_args < "$TMP/create-args"
[[ "${create_args[0]}" == 60 ]]
[[ "${create_args[1]}" == 400 ]]
[[ "${create_args[3]}" == 400 ]]
[[ "${create_args[4]}" == allowed-group-member ]]
[[ "${create_args[5]}" == -1001234567890 ]]
[[ "${create_args[6]}" == -1001234567890 ]]
[[ "${create_args[7]}" == 'Reseller Norte' ]]
grep -Fq 'HT-TRANSFERABLE-TEST' "$TMP/current-message"
grep -Fq 'Reseller Norte' "$TMP/current-message"
grep -Fq 'activada correctamente' "$TMP/current-message"
[[ "$(issued_key_get 11111111-2222-3333-4444-555555555555)" == 'HT-TRANSFERABLE-TEST' ]]

# Un visitante no puede generar por privado.
rm -f "$TMP/create-args" "$TMP/current-message"
current_chat_type='private'
current_chat_id='400'
actor_id='400'
actor_role='public'
comando=(/Keygen)
gerar_key
[[ ! -e "$TMP/create-args" ]]
grep -Fq 'Acceso no disponible' "$TMP/current-message"

# Un cliente autorizado puede generar múltiples keys transferibles; no se
# consulta ni bloquea por una licencia anterior del mismo Telegram ID.
current_chat_id='300'
actor_id='300'
actor_username='client_test'
actor_role='client'
comando=(/Keygen)
rm -f "$TMP/create-args"
gerar_key
[[ -e "$TMP/create-args" ]]
grep -Fq 'Cliente Store' "$TMP/current-message"

# Los argumentos manuales siguen prohibidos.
rm -f "$TMP/create-args" "$TMP/current-message"
comando=(/Keygen 999)
gerar_key
[[ ! -e "$TMP/create-args" ]]
grep -Fq 'Usa únicamente' "$TMP/current-message"

echo 'Role, reseller, group and transferable key flow tests passed.'
