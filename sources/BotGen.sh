#!/usr/bin/env bash
# TeleBotGen: administración por roles para Hex Tunnel.
set -Eeuo pipefail
umask 077

CIDdir="${TELEBOTGEN_STATE_DIR:-/etc/ADM-db}"
SRC="$CIDdir/sources"
REPOSITORY="${TELEBOTGEN_REPOSITORY:-Gh0stDeveloper/TeleBotGen}"
REF="${TELEBOTGEN_REF:-main}"

if [[ -r "$CIDdir/repository.env" ]]; then
    # shellcheck disable=SC1090
    source "$CIDdir/repository.env"
    REPOSITORY="${TELEBOTGEN_REPOSITORY:-$REPOSITORY}"
    REF="${TELEBOTGEN_REF:-$REF}"
fi
RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/${REF}"
LINE='============================'

install -d -m 700 "$CIDdir" "$SRC"

for command in curl jq openssl; do
    command -v "$command" >/dev/null 2>&1 || {
        apt-get update -qq
        apt-get install -y --no-install-recommends curl jq openssl ca-certificates
        break
    }
done

if [[ ! -s /bin/ShellBot.sh ]]; then
    curl -fsSL --retry 2 "$RAW_BASE/ShellBot.sh" -o /bin/ShellBot.sh
    chmod 700 /bin/ShellBot.sh
fi

# shellcheck source=/bin/ShellBot.sh
source /bin/ShellBot.sh
# shellcheck source=/dev/null
source "$SRC/license_api"
source "$SRC/roles"
source "$SRC/menu"
source "$SRC/ayuda"
source "$SRC/id"
source "$SRC/link"
source "$SRC/gerar_key"
source "$SRC/access"
source "$SRC/status"
source "$SRC/update"
source "$SRC/comandos"

roles_prepare_files
bot_token="$(tr -d '\r\n' < "$CIDdir/token" 2>/dev/null || true)"
[[ "$bot_token" =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{30,}$ ]] || {
    echo 'TeleBotGen: configura un token válido en /etc/ADM-db/token.' >&2
    exit 1
}
license_api_health >/dev/null || {
    echo 'TeleBotGen: GhostDeveloperLicenseServer no responde en 127.0.0.1:8080.' >&2
    exit 1
}
license_api_token >/dev/null || {
    echo 'TeleBotGen: no se puede leer el token administrativo local.' >&2
    exit 1
}

ShellBot.init --token "$bot_token" --monitor --flush --return map
ShellBot.username

send_html() {
    local chat_id="$1" text="$2" markup="${3:-}"
    if [[ -n "$markup" ]]; then
        ShellBot.sendMessage --chat_id "$chat_id" --text "$text" --parse_mode html --reply_markup "$markup"
    else
        ShellBot.sendMessage --chat_id "$chat_id" --text "$text" --parse_mode html
    fi
}

msj_fun() {
    send_html "$current_chat_id" "$(printf '%b' "$bot_retorno")"
}

send_to_actor() {
    local text="$1"
    send_html "$actor_id" "$(printf '%b' "$text")"
}

menu_print() {
    local button_name='botao_public'
    case "$actor_role" in
        admin) button_name='botao_admin' ;;
        reseller) button_name='botao_reseller' ;;
        client) button_name='botao_client' ;;
    esac
    send_html "$current_chat_id" "$(printf '%b' "$bot_retorno")" \
        "$(ShellBot.InlineKeyboardMarkup -b "$button_name")"
}

botao_admin=''
botao_reseller=''
botao_client=''
botao_public=''

ShellBot.InlineKeyboardButton --button botao_admin --line 1 --text 'Generar key' --callback_data '/keygen'
ShellBot.InlineKeyboardButton --button botao_admin --line 1 --text 'Licencias' --callback_data '/licenses'
ShellBot.InlineKeyboardButton --button botao_admin --line 2 --text 'Revendedores' --callback_data '/resellers'
ShellBot.InlineKeyboardButton --button botao_admin --line 2 --text 'Grupos' --callback_data '/groups'
ShellBot.InlineKeyboardButton --button botao_admin --line 3 --text 'Estado API' --callback_data '/api'
ShellBot.InlineKeyboardButton --button botao_admin --line 3 --text 'Instalador' --callback_data '/install'

ShellBot.InlineKeyboardButton --button botao_reseller --line 1 --text 'Generar key' --callback_data '/keygen'
ShellBot.InlineKeyboardButton --button botao_reseller --line 1 --text 'Mis licencias' --callback_data '/mykeys'
ShellBot.InlineKeyboardButton --button botao_reseller --line 2 --text 'Instalador' --callback_data '/install'
ShellBot.InlineKeyboardButton --button botao_reseller --line 2 --text 'Ayuda' --callback_data '/help'

ShellBot.InlineKeyboardButton --button botao_client --line 1 --text 'Mi licencia' --callback_data '/license'
ShellBot.InlineKeyboardButton --button botao_client --line 1 --text 'Instalador' --callback_data '/install'
ShellBot.InlineKeyboardButton --button botao_client --line 2 --text 'Actualización' --callback_data '/upgrade'
ShellBot.InlineKeyboardButton --button botao_client --line 2 --text 'Mi ID' --callback_data '/id'

ShellBot.InlineKeyboardButton --button botao_public --line 1 --text 'Mi ID' --callback_data '/id'
ShellBot.InlineKeyboardButton --button botao_public --line 1 --text 'Sitio oficial' --callback_data website --url 'https://ghostdeveloper.duckdns.org/'
ShellBot.InlineKeyboardButton --button botao_public --line 2 --text '@Gh0stDeveloper' --callback_data developer1 --url 'https://t.me/Gh0stDeveloper'
ShellBot.InlineKeyboardButton --button botao_public --line 2 --text '@Jotchua_DevzZ' --callback_data developer2 --url 'https://t.me/Jotchua_DevzZ'

while true; do
    ShellBot.getUpdates --limit 100 --offset "$(ShellBot.OffsetNext)" --timeout 30
    for id in $(ShellBot.ListUpdates); do
        current_chat_id="${message_chat_id[$id]:-${callback_query_message_chat_id[$id]:-}}"
        actor_id="${message_from_id[$id]:-${callback_query_from_id[$id]:-}}"
        actor_username="${message_from_username[$id]:-${callback_query_from_username[$id]:-}}"
        raw_command="${message_text[$id]:-${callback_query_data[$id]:-}}"
        reply_user_id="${message_reply_to_message_from_id[$id]:-}"
        reply_username="${message_reply_to_message_from_username[$id]:-}"

        [[ -n "$current_chat_id" && "$actor_id" =~ ^[0-9]+$ ]] || continue
        read -r -a comando <<< "$raw_command"
        command_name="${comando[0]:-}"
        command_name="${command_name%%@*}"
        comando[0]="$command_name"
        group_is_chat "$current_chat_id" && current_chat_type='group' || current_chat_type='private'
        actor_resolve_role "$actor_id"

        if [[ "$current_chat_type" == group ]] && ! group_is_allowed "$current_chat_id"; then
            if [[ "$actor_role" == admin && "$command_name" == /allowgroup ]]; then
                :
            elif [[ "$command_name" =~ ^/[Ii][Dd]$ ]]; then
                :
            else
                continue
            fi
        fi

        comand
    done
done
