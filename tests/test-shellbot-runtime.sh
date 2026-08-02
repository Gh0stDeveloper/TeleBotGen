#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Validación estática: ShellBot no debe ejecutarse bajo errexit/nounset y el
# token no debe pasar como argumento visible al proceso curl.
grep -Fq 'set +e' "$ROOT/sources/BotGen.sh"
grep -Fq 'set +u' "$ROOT/sources/BotGen.sh"
! grep -Eq '^set -[^[:space:]]*[eu]' "$ROOT/sources/BotGen.sh"
! grep -Eq 'ShellBot\.init.*--monitor' "$ROOT/sources/BotGen.sh"
! grep -Eq '^[[:space:]]*ShellBot\.username[[:space:]]*$' "$ROOT/sources/BotGen.sh"
! grep -Fq 'if ! ShellBot.init' "$ROOT/sources/BotGen.sh"
grep -Fq 'command curl --config' "$ROOT/sources/BotGen.sh"
grep -Fq 'shellbot_init_rc=$?' "$ROOT/sources/BotGen.sh"
grep -Fq '${_SHELLBOT_INIT_:-}' "$ROOT/sources/BotGen.sh"
grep -Fq 'declare -F ShellBot.getUpdates' "$ROOT/sources/BotGen.sh"
! grep -Fq 'if ! ShellBot.getUpdates' "$ROOT/sources/BotGen.sh"
grep -Fq 'ShellBot.getUpdates --limit 100' "$ROOT/sources/BotGen.sh"
grep -Fq 'se procesan siempre las actualizaciones cargadas' "$ROOT/sources/BotGen.sh"

printf 'ShellBot runtime hardening checks passed.\n'
