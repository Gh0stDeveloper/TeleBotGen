#!/usr/bin/env bash
# TeleBotGen: gestión por roles y notificaciones de activación.
set +e
set +u
set -o pipefail
umask 077

CIDdir="${TELEBOTGEN_STATE_DIR:-/etc/ADM-db}"
SRC="$CIDdir/sources"
LINE='━━━━━━━━━━━━━━━━━━━━'

install -d -m 700 "$CIDdir" "$SRC"
for required_command in curl jq openssl flock; do
    command -v "$required_command" >/dev/null 2>&1 || {
        echo "TeleBotGen: falta la dependencia requerida: $required_command" >&2
        exit 1
    }
done
[[ -s /bin/ShellBot.sh ]] || {
    echo 'TeleBotGen: falta /bin/ShellBot.sh; ejecuta el despliegue como root.' >&2
    exit 1
}

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
source "$SRC/notifications"
source "$SRC/comandos"

# Oculta el token de Telegram de argv y de los listados de procesos.
curl() {
    local argument telegram_url='' config_file='' rc
    local -a sanitized_arguments=()
    for argument in "$@"; do
        if [[ "$argument" == https://api.telegram.org/bot* ]]; then
            telegram_url="$argument"
        else
            sanitized_arguments+=("$argument")
        fi
    done
    if [[ -z "$telegram_url" ]]; then
        command curl "${sanitized_arguments[@]}"
        return $?
    fi
    config_file="$(mktemp "$CIDdir/.telegram-curl.XXXXXX")" || return 1
    chmod 600 "$config_file"
    printf 'url = "%s"\n' "$telegram_url" > "$config_file"
    command curl --config "$config_file" "${sanitized_arguments[@]}"
    rc=$?
    rm -f "$config_file"
    return "$rc"
}

roles_prepare_files
bot_token="$(tr -d '\r\n' < "$CIDdir/token" 2>/dev/null || true)"
[[ "$bot_token" =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{30,}$ ]] || {
    echo 'TeleBotGen: configura un token válido.' >&2
    exit 1
}
license_api_health >/dev/null || {
    echo 'TeleBotGen: el servicio requerido no está disponible.' >&2
    exit 1
}
license_api_token >/dev/null || {
    echo 'TeleBotGen: no se pudo cargar la autorización local.' >&2
    exit 1
}

ShellBot.init --token "$bot_token" --return map
shellbot_init_rc=$?
if [[ "${_SHELLBOT_INIT_:-}" != 1 ]] || ! declare -F ShellBot.getUpdates >/dev/null; then
    echo "TeleBotGen: no pudo inicializar Telegram (código $shellbot_init_rc)." >&2
    exit 1
fi
unset shellbot_init_rc bot_token

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

menu_print() {
    local button_name='botao_public'
    if [[ "$current_chat_type" == group ]]; then
        button_name='botao_group'
    else
        case "$actor_role" in
            admin) button_name='botao_admin' ;;
            reseller) button_name='botao_reseller' ;;
            client) button_name='botao_client' ;;
        esac
    fi
    send_html "$current_chat_id" "$(printf '%b' "$bot_retorno")" \
        "$(ShellBot.InlineKeyboardMarkup -b "$button_name")"
}

botao_admin=''
botao_reseller=''
botao_client=''
botao_public=''
botao_group=''

ShellBot.InlineKeyboardButton --button botao_admin --line 1 --text '🎟️ Generar key' --callback_data '/keygen'
ShellBot.InlineKeyboardButton --button botao_admin --line 1 --text '🏷️ Mi reseller' --callback_data '/reseller'
ShellBot.InlineKeyboardButton --button botao_admin --line 2 --text '📋 Mis keys' --callback_data '/mykeys'
ShellBot.InlineKeyboardButton --button botao_admin --line 2 --text '👥 Clientes' --callback_data '/clients'
ShellBot.InlineKeyboardButton --button botao_admin --line 3 --text '🌐 Grupos' --callback_data '/groups'
ShellBot.InlineKeyboardButton --button botao_admin --line 3 --text '⏳ Tiempo key' --callback_data '/keytime'
ShellBot.InlineKeyboardButton --button botao_admin --line 4 --text '🔗 Instalador' --callback_data '/install'
ShellBot.InlineKeyboardButton --button botao_admin --line 4 --text '📖 Ayuda' --callback_data '/help'

ShellBot.InlineKeyboardButton --button botao_reseller --line 1 --text '🎟️ Generar key' --callback_data '/keygen'
ShellBot.InlineKeyboardButton --button botao_reseller --line 1 --text '🏷️ Mi reseller' --callback_data '/reseller'
ShellBot.InlineKeyboardButton --button botao_reseller --line 2 --text '📋 Mis keys' --callback_data '/mykeys'
ShellBot.InlineKeyboardButton --button botao_reseller --line 2 --text '👥 Clientes' --callback_data '/clients'
ShellBot.InlineKeyboardButton --button botao_reseller --line 3 --text '🌐 Mis grupos' --callback_data '/groups'
ShellBot.InlineKeyboardButton --button botao_reseller --line 3 --text '🔗 Instalador' --callback_data '/install'
ShellBot.InlineKeyboardButton --button botao_reseller --line 4 --text '📖 Ayuda' --callback_data '/help'

ShellBot.InlineKeyboardButton --button botao_client --line 1 --text '🎟️ Generar key' --callback_data '/keygen'
ShellBot.InlineKeyboardButton --button botao_client --line 1 --text '🏷️ Mi reseller' --callback_data '/reseller'
ShellBot.InlineKeyboardButton --button botao_client --line 2 --text '📋 Mis keys' --callback_data '/mykeys'
ShellBot.InlineKeyboardButton --button botao_client --line 2 --text '🔗 Instalador' --callback_data '/install'
ShellBot.InlineKeyboardButton --button botao_client --line 3 --text '📖 Ayuda' --callback_data '/help'
ShellBot.InlineKeyboardButton --button botao_client --line 3 --text '🆔 Mi ID' --callback_data '/id'

ShellBot.InlineKeyboardButton --button botao_public --line 1 --text '🌐 Hex Tunnel' --callback_data website --url "$HEXTUNNEL_PUBLIC_URL"
ShellBot.InlineKeyboardButton --button botao_public --line 2 --text '📖 Ayuda' --callback_data '/help'
ShellBot.InlineKeyboardButton --button botao_public --line 2 --text '🆔 Mi ID' --callback_data '/id'

ShellBot.InlineKeyboardButton --button botao_group --line 1 --text '🎟️ Generar key' --callback_data '/keygen'
ShellBot.InlineKeyboardButton --button botao_group --line 1 --text '🔗 Instalador' --callback_data '/install'
ShellBot.InlineKeyboardButton --button botao_group --line 2 --text '📖 Ayuda' --callback_data '/help'
ShellBot.InlineKeyboardButton --button botao_group --line 2 --text '🆔 IDs' --callback_data '/id'

while true; do
    ShellBot.getUpdates --limit 100 --offset "$(ShellBot.OffsetNext)" --timeout 10

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
            case "$command_name" in
                /start|/Start|/menu|/Menu|/help|/Help|/ayuda|/Ayuda|/id|/ID) ;;
                /allowgroup|/permitirgrupo)
                    [[ "$actor_role" == admin || "$actor_role" == reseller ]] || continue
                    ;;
                *) continue ;;
            esac
        fi

        comand
    done

    process_activation_events || true
done
