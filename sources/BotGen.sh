#!/usr/bin/env bash
# TeleBotGen: administración por roles para Hex Tunnel.
# ShellBot 6.x utiliza estados distintos de cero como control interno y no es
# compatible con errexit/nounset. Los errores críticos se validan explícitamente.
set +e
set +u
set -o pipefail
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

for required_command in curl jq openssl; do
    command -v "$required_command" >/dev/null 2>&1 || {
        apt-get update -qq
        apt-get install -y --no-install-recommends curl jq openssl ca-certificates
        break
    }
done

if [[ ! -s /bin/ShellBot.sh ]]; then
    command curl -fsSL --retry 2 "$RAW_BASE/ShellBot.sh" -o /bin/ShellBot.sh
    chmod 700 /bin/ShellBot.sh
fi

# ShellBot utiliza variables internas opcionales y estados no cero de control.
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

# Evita que el token incluido en la URL de Telegram aparezca en argv, ps,
# systemctl status o el CGroup. La URL se entrega a curl mediante un archivo
# temporal privado dentro del directorio de estado (modo 700).
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

# ShellBot.init puede devolver 1 aun cuando inicializa correctamente. Por eso
# se comprueba el estado interno y la existencia de las funciones cargadas.
ShellBot.init --token "$bot_token" --return map
shellbot_init_rc=$?
if [[ "${_SHELLBOT_INIT_:-}" != 1 ]] || ! declare -F ShellBot.getUpdates >/dev/null; then
    echo "TeleBotGen: ShellBot no pudo inicializar el bot de Telegram (código $shellbot_init_rc)." >&2
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

send_to_actor() {
    local text="$1"
    send_html "$actor_id" "$(printf '%b' "$text")"
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

ShellBot.InlineKeyboardButton --button botao_admin --line 1 --text 'Generar mi key' --callback_data '/keygen'
ShellBot.InlineKeyboardButton --button botao_admin --line 1 --text 'Duración keys' --callback_data '/keytime'
ShellBot.InlineKeyboardButton --button botao_admin --line 2 --text 'Licencias' --callback_data '/licenses'
ShellBot.InlineKeyboardButton --button botao_admin --line 2 --text 'Grupos' --callback_data '/groups'
ShellBot.InlineKeyboardButton --button botao_admin --line 3 --text 'Estado API' --callback_data '/api'
ShellBot.InlineKeyboardButton --button botao_admin --line 3 --text 'Instalador' --callback_data '/install'

ShellBot.InlineKeyboardButton --button botao_reseller --line 1 --text 'Generar mi key' --callback_data '/keygen'
ShellBot.InlineKeyboardButton --button botao_reseller --line 1 --text 'Mi licencia' --callback_data '/license'
ShellBot.InlineKeyboardButton --button botao_reseller --line 2 --text 'Instalador' --callback_data '/install'
ShellBot.InlineKeyboardButton --button botao_reseller --line 2 --text 'Ayuda' --callback_data '/help'

ShellBot.InlineKeyboardButton --button botao_client --line 1 --text 'Mi licencia' --callback_data '/license'
ShellBot.InlineKeyboardButton --button botao_client --line 1 --text 'Instalador' --callback_data '/install'
ShellBot.InlineKeyboardButton --button botao_client --line 2 --text 'Actualización' --callback_data '/upgrade'
ShellBot.InlineKeyboardButton --button botao_client --line 2 --text 'Mi ID' --callback_data '/id'

ShellBot.InlineKeyboardButton --button botao_public --line 1 --text 'Generar mi key' --callback_data '/keygen'
ShellBot.InlineKeyboardButton --button botao_public --line 1 --text 'Mi ID' --callback_data '/id'
ShellBot.InlineKeyboardButton --button botao_public --line 2 --text 'Sitio oficial' --callback_data website --url 'https://ghostdeveloper.duckdns.org/'
ShellBot.InlineKeyboardButton --button botao_public --line 3 --text '@Gh0stDeveloper' --callback_data developer1 --url 'https://t.me/Gh0stDeveloper'
ShellBot.InlineKeyboardButton --button botao_public --line 3 --text '@Jotchua_DevzZ' --callback_data developer2 --url 'https://t.me/Jotchua_DevzZ'

ShellBot.InlineKeyboardButton --button botao_group --line 1 --text 'Generar mi key' --callback_data '/keygen'
ShellBot.InlineKeyboardButton --button botao_group --line 1 --text 'Mi licencia' --callback_data '/license'
ShellBot.InlineKeyboardButton --button botao_group --line 2 --text 'Mi ID' --callback_data '/id'
ShellBot.InlineKeyboardButton --button botao_group --line 2 --text 'Ayuda' --callback_data '/help'

while true; do
    # ShellBot.getUpdates devuelve 1 después de poblar correctamente sus arrays
    # cuando no hay archivo de log configurado. El código de retorno no permite
    # distinguir éxito de error; se procesan siempre las actualizaciones cargadas.
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
