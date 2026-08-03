#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# ShellBot no debe ejecutarse bajo errexit/nounset y el token no debe pasar
# como argumento visible al proceso curl.
grep -Fq 'set +e' "$ROOT/sources/BotGen.sh"
grep -Fq 'set +u' "$ROOT/sources/BotGen.sh"
! grep -Eq '^set -[^[:space:]]*[eu]' "$ROOT/sources/BotGen.sh"
! grep -Eq 'ShellBot\.init.*--monitor' "$ROOT/sources/BotGen.sh"
! grep -Fq 'if ! ShellBot.init' "$ROOT/sources/BotGen.sh"
grep -Fq 'command curl --config' "$ROOT/sources/BotGen.sh"
grep -Fq 'shellbot_init_rc=$?' "$ROOT/sources/BotGen.sh"
grep -Fq '${_SHELLBOT_INIT_:-}' "$ROOT/sources/BotGen.sh"
grep -Fq 'declare -F ShellBot.getUpdates' "$ROOT/sources/BotGen.sh"
! grep -Fq 'if ! ShellBot.getUpdates' "$ROOT/sources/BotGen.sh"
grep -Fq 'ShellBot.getUpdates --limit 100' "$ROOT/sources/BotGen.sh"
grep -Fq 'source "$SRC/notifications"' "$ROOT/sources/BotGen.sh"
grep -Fq 'process_activation_events || true' "$ROOT/sources/BotGen.sh"
grep -Fq 'HEXTUNNEL_PUBLIC_URL' "$ROOT/sources/BotGen.sh"

# El runtime del bot no puede intentar instalar paquetes ni modificar /bin.
! grep -Fq 'apt-get install' "$ROOT/sources/BotGen.sh"
! grep -Fq 'command curl -fsSL' "$ROOT/sources/BotGen.sh"
! grep -Fq 'repository.env' "$ROOT/sources/BotGen.sh"

printf 'ShellBot runtime and notification checks passed.\n'
