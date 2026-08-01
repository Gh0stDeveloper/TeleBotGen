#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export TELEBOTGEN_ADMIN_FILE="$TMP/Admin-ID"
export TELEBOTGEN_RESELLER_FILE="$TMP/Reseller-ID"
export TELEBOTGEN_GROUP_FILE="$TMP/Allowed-Groups"
export TELEBOTGEN_LICENSE_ADMIN_TOKEN_FILE="$TMP/admin-token"
printf 'test-token\n' > "$TELEBOTGEN_LICENSE_ADMIN_TOKEN_FILE"
chmod 600 "$TELEBOTGEN_LICENSE_ADMIN_TOKEN_FILE"

# shellcheck source=/dev/null
source "$ROOT/sources/license_api"
# shellcheck source=/dev/null
source "$ROOT/sources/roles"
roles_prepare_files

printf '100\n' > "$TELEBOTGEN_ADMIN_FILE"
printf '200\n' > "$TELEBOTGEN_RESELLER_FILE"
printf '%s\n' '-1001234567890' > "$TELEBOTGEN_GROUP_FILE"

role_is_admin 100
! role_is_admin 200
role_is_reseller 200
group_is_allowed -1001234567890
! group_is_allowed -100999
role_validate_duration reseller 43200
! role_validate_duration reseller 43201
role_validate_duration admin 525600

license_api_all() {
    cat <<'JSON'
{
  "items": [
    {
      "id": "old",
      "key_prefix": "HT-OLD",
      "product": "hextunnel",
      "owner_telegram_id": "300",
      "owner_username": "client",
      "status": "expired",
      "created_at": "2025-01-01T00:00:00Z",
      "expires_at": "2025-01-02T00:00:00Z",
      "activation_limit": 1,
      "activation_count": 1,
      "bound_ip": null,
      "activated_at": null,
      "revoked_at": null,
      "revoke_reason": null,
      "metadata": {}
    },
    {
      "id": "active",
      "key_prefix": "HT-ACTIVE",
      "product": "hextunnel",
      "owner_telegram_id": "300",
      "owner_username": "client",
      "status": "active",
      "created_at": "2026-01-01T00:00:00Z",
      "expires_at": "2099-01-01T00:00:00Z",
      "activation_limit": 1,
      "activation_count": 0,
      "bound_ip": null,
      "activated_at": null,
      "revoked_at": null,
      "revoke_reason": null,
      "metadata": {}
    }
  ]
}
JSON
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

[[ "$(license_human_duration 90060)" == '1 día(s), 1 hora(s) y 1 minuto(s)' ]]
command_text="$(hextunnel_install_command)"
grep -Fq 'command -v curl' <<< "$command_text"
grep -Fq 'https://ghostdeveloper.duckdns.org/install.sh' <<< "$command_text"
[[ "$(hextunnel_upgrade_command)" == 'sudo hextunnel-upgrade' ]]

echo 'Role and license flow tests passed.'
