#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="$(mktemp -d /tmp/telebotgen-key-test.XXXXXX)"
trap 'rm -rf "${WORK:-}"' EXIT

export HEXGEN_KEY_ROOT="$WORK/keys"
export HEXGEN_STATE_ROOT="$WORK/state"
export HEXGEN_LOG_FILE="$WORK/license.log"
export HEXGEN_PUBLIC_HOST='203.0.113.10'
export HEXGEN_PORT=8888
export HEXGEN_KEY_TTL_MINUTES=10
mkdir -p "$HEXGEN_KEY_ROOT" "$HEXGEN_STATE_ROOT"

# shellcheck source=../sources/gerar_key
source "$ROOT/sources/gerar_key"

key="$(hexgen_create_key 123456789)"
[[ "$key" == HexGen/* ]]
decoded="$(hexgen_key_codec "${key#HexGen/}")"
endpoint="${decoded%/*}"
token="${decoded##*/}"
[[ "$endpoint" == '203.0.113.10:8888' ]]
[[ "$token" =~ ^[0-9a-f]{40}$ ]]
[[ -f "$HEXGEN_KEY_ROOT/$token/HexGen" ]]
[[ -f "$HEXGEN_KEY_ROOT/$token/metadata.env" ]]
[[ "$(stat -c '%a' "$HEXGEN_KEY_ROOT/$token/metadata.env")" == 600 ]]

do_request() {
    printf 'GET /%s/HexGen/198.51.100.77 HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n' "$token" \
        | SOCAT_PEERADDR='198.51.100.77' \
          HEXGEN_KEY_ROOT="$HEXGEN_KEY_ROOT" \
          HEXGEN_STATE_ROOT="$HEXGEN_STATE_ROOT" \
          HEXGEN_LOG_FILE="$HEXGEN_LOG_FILE" \
          bash "$ROOT/http-server.sh" --handle
}

first="$(do_request)"
grep -q $'HTTP/1.1 200 OK\r' <<< "$first"
[[ "${first##*$'\r\n\r\n'}" == HexGen ]]
[[ ! -e "$HEXGEN_KEY_ROOT/$token" ]]
grep -q "$token" "$HEXGEN_LOG_FILE"
[[ "$(stat -c '%a' "$HEXGEN_LOG_FILE")" == 600 ]]

second="$(do_request)"
[[ "${second##*$'\r\n\r\n'}" == 'KEY INVALIDA!' ]]

invalid_method="$(printf 'POST /%s/HexGen/198.51.100.77 HTTP/1.1\r\n\r\n' "$token" \
    | HEXGEN_KEY_ROOT="$HEXGEN_KEY_ROOT" \
      HEXGEN_STATE_ROOT="$HEXGEN_STATE_ROOT" \
      HEXGEN_LOG_FILE="$HEXGEN_LOG_FILE" \
      bash "$ROOT/http-server.sh" --handle)"
grep -q $'HTTP/1.1 405 Method Not Allowed\r' <<< "$invalid_method"

printf 'TeleBotGen one-time key flow: ok\n'
