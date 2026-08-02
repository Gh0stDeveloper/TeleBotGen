#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export TELEBOTGEN_UPDATE_REQUEST_FILE="$TMP/update.request"
role_is_admin() { [[ "$1" == 100 ]]; }
msj_fun() { printf '%s\n' "$bot_retorno" > "$TMP/message"; }
# shellcheck source=/dev/null
source "$ROOT/sources/update"

actor_id=200
update
[[ ! -e "$TELEBOTGEN_UPDATE_REQUEST_FILE" ]]
grep -Fq 'Solo el administrador' "$TMP/message"

actor_id=100
update
[[ -s "$TELEBOTGEN_UPDATE_REQUEST_FILE" ]]
grep -Fxq 'requested_by=100' "$TELEBOTGEN_UPDATE_REQUEST_FILE"
grep -Eq '^requested_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$TELEBOTGEN_UPDATE_REQUEST_FILE"
grep -Fq 'Actualización solicitada' "$TMP/message"

update
grep -Fq 'actualización pendiente o en curso' "$TMP/message"

echo 'Secure update request flow passed.'
