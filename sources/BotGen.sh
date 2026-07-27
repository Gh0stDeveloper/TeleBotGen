#!/usr/bin/env bash
# Telegram administration and Hex Tunnel license bot.
set -Eeuo pipefail
umask 077

CIDdir="/etc/ADM-db"
SRC="${CIDdir}/sources"
CID="${CIDdir}/User-ID"
keytxt="/etc/http-shell"
REPOSITORY="${TELEBOTGEN_REPOSITORY:-Gh0stDeveloper/TeleBotGen}"
REF="${TELEBOTGEN_REF:-main}"

if [[ -r "${CIDdir}/repository.env" ]]; then
    # shellcheck disable=SC1091
    source "${CIDdir}/repository.env"
    REPOSITORY="${TELEBOTGEN_REPOSITORY:-$REPOSITORY}"
    REF="${TELEBOTGEN_REF:-$REF}"
fi
RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/${REF}"

mkdir -p "$CIDdir" "$SRC" "$keytxt"
chmod 700 "$CIDdir" "$SRC" "$keytxt"
[[ -e "$CID" ]] || : > "$CID"

if ! command -v jq >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y --no-install-recommends jq ca-certificates curl
fi

if [[ ! -s /bin/ShellBot.sh ]]; then
    curl -fsSL --retry 2 "$RAW_BASE/ShellBot.sh" -o /bin/ShellBot.sh
    chmod 700 /bin/ShellBot.sh
fi

LINE="==========================="

# shellcheck source=/bin/ShellBot.sh
source /bin/ShellBot.sh
# shellcheck source=/dev/null
source "$SRC/menu"
source "$SRC/ayuda"
source "$SRC/cache"
source "$SRC/invalido"
source "$SRC/status"
source "$SRC/reinicio"
source "$SRC/myip"
source "$SRC/id"
source "$SRC/back_ID"
source "$SRC/link"
source "$SRC/listID"
source "$SRC/gerar_key"
source "$SRC/power"
source "$SRC/comandos"
source "$SRC/update"
source "$SRC/donar"

bot_token="$(tr -d '\r\n' < "$CIDdir/token" 2>/dev/null || true)"
[[ -n "$bot_token" && "$bot_token" != null ]] || {
    echo 'TeleBotGen: falta configurar /etc/ADM-db/token.' >&2
    exit 1
}

ShellBot.init --token "$bot_token" --monitor --flush --return map
ShellBot.username

reply() {
    local var
    [[ -n "${callback_query_message_chat_id[$id]:-}" ]] \
        && var="${callback_query_message_chat_id[$id]}" \
        || var="${message_chat_id[$id]}"
    ShellBot.sendMessage --chat_id "$var" \
        --text "$comando" \
        --parse_mode html \
        --reply_markup "$(ShellBot.ForceReply)"
    [[ "${callback_query_data[$id]:-}" == /del || "${message_text[$id]:-}" == /del ]] && listID_src
}

menu_print() {
    local var
    [[ -n "${callback_query_message_chat_id[$id]:-}" ]] \
        && var="${callback_query_message_chat_id[$id]}" \
        || var="${message_chat_id[$id]}"
    if ! grep -Fxq "$chatuser" <<< "$permited"; then
        ShellBot.sendMessage --chat_id "$var" \
            --text "<i>$(printf '%b' "$bot_retorno")</i>" \
            --parse_mode html \
            --reply_markup "$(ShellBot.InlineKeyboardMarkup -b 'botao_user')"
    else
        ShellBot.sendMessage --chat_id "$var" \
            --text "<i>$(printf '%b' "$bot_retorno")</i>" \
            --parse_mode html \
            --reply_markup "$(ShellBot.InlineKeyboardMarkup -b 'botao_conf')"
    fi
}

download_file() {
    rm -f "$CID"
    ShellBot.getFile --file_id "${message_document_file_id[$id]}"
    ShellBot.downloadFile --file_path "${return[file_path]}" --dir "$CIDdir"
    local bot_retorno="ID permitidos\n$LINE\nArchivo restaurado correctamente.\n$LINE"
    ShellBot.sendMessage --chat_id "${message_chat_id[$id]}" \
        --reply_to_message_id "${message_message_id[$id]}" \
        --text "<i>$(printf '%b' "$bot_retorno")</i>" \
        --parse_mode html
}

msj_add() {
    ShellBot.sendMessage --chat_id "$1" --text "<i>$(printf '%b' "$bot_retor")</i>" --parse_mode html
}

upfile_fun() {
    local var
    [[ -n "${callback_query_message_chat_id[$id]:-}" ]] \
        && var="${callback_query_message_chat_id[$id]}" \
        || var="${message_chat_id[$id]}"
    ShellBot.sendDocument --chat_id "$var" --document "@$1"
}

msj_fun() {
    local var
    [[ -n "${callback_query_message_chat_id[$id]:-}" ]] \
        && var="${callback_query_message_chat_id[$id]}" \
        || var="${message_chat_id[$id]}"
    ShellBot.sendMessage --chat_id "$var" \
        --text "$(printf '%b' "$bot_retorno")" \
        --parse_mode html
}

msj_donar() {
    local var
    [[ -n "${callback_query_message_chat_id[$id]:-}" ]] \
        && var="${callback_query_message_chat_id[$id]}" \
        || var="${message_chat_id[$id]}"
    ShellBot.sendMessage --chat_id "$var" \
        --text "<i>$(printf '%b' "$bot_retorno")</i>" \
        --parse_mode html \
        --reply_markup "$(ShellBot.InlineKeyboardMarkup -b 'botao_donar')"
}

botao_conf=''
botao_user=''
botao_donar=''
ShellBot.InlineKeyboardButton --button 'botao_conf' --line 1 --text 'Autorizar ID' --callback_data '/add'
ShellBot.InlineKeyboardButton --button 'botao_conf' --line 1 --text 'Revocar ID' --callback_data '/del'
ShellBot.InlineKeyboardButton --button 'botao_conf' --line 2 --text 'Lista' --callback_data '/list'
ShellBot.InlineKeyboardButton --button 'botao_conf' --line 2 --text 'Mi ID' --callback_data '/ID'
ShellBot.InlineKeyboardButton --button 'botao_conf' --line 3 --text 'Servidor' --callback_data '/power'
ShellBot.InlineKeyboardButton --button 'botao_conf' --line 3 --text 'Menú' --callback_data '/menu'
ShellBot.InlineKeyboardButton --button 'botao_conf' --line 4 --text 'Generar key' --callback_data '/keygen'
ShellBot.InlineKeyboardButton --button 'botao_user' --line 1 --text 'Generar key' --callback_data '/keygen'
ShellBot.InlineKeyboardButton --button 'botao_user' --line 2 --text 'Instalador' --callback_data '/install'
ShellBot.InlineKeyboardButton --button 'botao_donar' --line 1 --text 'Soporte' --callback_data '1' --url 'https://t.me/Gh0stDeveloper'

while true; do
    ShellBot.getUpdates --limit 100 --offset "$(ShellBot.OffsetNext)" --timeout 30
    for id in $(ShellBot.ListUpdates); do
        chatuser="${message_chat_id[$id]:-${callback_query_from_id[$id]:-}}"
        chatuser="${chatuser#-}"
        comando=("${message_text[$id]:-${callback_query_data[$id]:-}}")
        [[ -e "$CIDdir/Admin-ID" ]] || printf 'null\n' > "$CIDdir/Admin-ID"
        permited="$(cat "$CIDdir/Admin-ID")"
        comand
    done
done
