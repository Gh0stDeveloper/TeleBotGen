#!/bin/bash

IVAR="/etc/http-instas"
onliCHECK="/var/www/html/HexGen"
LIST="$(echo "HexGen" | rev)"

[[ -d "$onliCHECK" ]] || mkdir -p "$onliCHECK"

install_fun() {
    apt-get install -y socat
}

fun_ip() {
    _hora=$(date '+%d/%m/%Y-%H:%M:%S')

    if [[ -e /bin/ejecutar/IPcgh ]]; then
        IP="$(cat /bin/ejecutar/IPcgh)"
    else
        MEU_IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
        MEU_IP2=$(wget -qO- ipv4.icanhazip.com)

        [[ -n "$MEU_IP2" ]] && IP="$MEU_IP2" || IP="$MEU_IP"

        mkdir -p /bin/ejecutar
        echo "$IP" > /bin/ejecutar/IPcgh
    fi
}

ofus() {
    unset txtofus
    local str="$1"
    local number=$(expr length "$str")
    local c

    for ((i=1; i<=number; i++)); do
        c=$(echo "$str" | cut -b "$i")

        case "$c" in
            ".") c="*";;
            "*") c=".";;
            "1") c="@";;
            "@") c="1";;
            "2") c="?";;
            "?") c="2";;
            "4") c="%";;
            "%") c="4";;
            "-") c="K";;
            "K") c="-";;
        esac

        txtofus+="$c"
    done

    echo "$txtofus" | rev
}

listen_fun() {
    PORTA="8888"
    PROGRAMA="/bin/http-server.sh"
    socat TCP-LISTEN:${PORTA},fork,reuseaddr,linger=0 EXEC:"${PROGRAMA}"
}

server_fun() {
    fun_ip

    PORTA="8888"
    DIR="/etc/http-shell"

    mkdir -p "$DIR"
    read -t 5 URL || exit 0

    KEYZ=($(echo "$URL" | cut -d' ' -f2 | awk -F "/" '{print $2, $3, $4}'))

    KEY="${KEYZ[0]}"
    ARQ="${KEYZ[1]}"
    USRIP="${KEYZ[2]}"

    [[ -z "$KEY" ]] && KEY="ERRO"
    [[ -z "$ARQ" ]] && ARQ="ERRO"
    [[ -z "$USRIP" ]] && USRIP="ERRO"

    FILE2="${DIR}/${KEY}"
    FILE="${DIR}/${KEY}/${ARQ}"

    ENV_ARQ="False"

    if [[ -e "$FILE" ]]; then
        ENV_ARQ="True"

        if [[ -e "${FILE2}/GERADOR" && "$USRIP" != "ERRO" ]]; then
            FILE="${DIR}/ERROR-KEY"
            echo "KEY DE GENERADOR!" > "$FILE"
            ENV_ARQ="False"

        elif [[ ! -e "${FILE2}/GERADOR" && "$USRIP" == "ERRO" ]]; then
            FILE="${DIR}/ERROR-KEY"
            echo "KEY DE HEXGEN!" > "$FILE"
            ENV_ARQ="False"
        fi

    else
        FILE="${DIR}/ERROR-KEY"
        echo "KEY INVALIDA!" > "$FILE"
    fi

    cat << EOF
HTTP/1.1 200 Found
Date: $(date)
Server: HexGenHTTP
Content-Length: $(wc -c < "$FILE")
Connection: close
Content-Type: text/html; charset=utf-8

$(cat "$FILE")
EOF

    if [[ "$ENV_ARQ" = "True" ]]; then
        (
            KEY_NAME="$(cat "${FILE2}.name" 2>/dev/null)"
            USED_TIME="$(date '+%d/%m/%Y %H:%M:%S')"

            mkdir -p "/var/www/html/$KEY"
            mkdir -p "/var/www/$KEY"

            TIME="20+"

            while IFS= read -r arqs; do
                [[ -z "$arqs" ]] && continue

                cp "${FILE2}/${arqs}" "/var/www/html/$KEY/" 2>/dev/null
                cp "${FILE2}/${arqs}" "/var/www/$KEY/" 2>/dev/null

                TIME+="1+"
            done < "$FILE"

            _key="HexGen/$(ofus "${IP}:${PORTA}/${KEY}")"
[24/07/2026 08:47 p. m.] Jotchua DevzZ ['']: echo "${KEY_NAME} | ${USRIP} | ${_key} | ${USED_TIME}" \
                > "/var/www/html/$KEY/checkIP.log"

            echo "${KEY_NAME} | ${USRIP} | ${_key} | ${USED_TIME}" \
                > "/var/www/$KEY/checkIP.log"

            RESELL="$(cat "/var/www/$KEY/menu_credito" 2>/dev/null)"

            TIME=$(echo "${TIME}0" | bc)

            sleep "${TIME}s"

            rm -rf "/var/www/html/$KEY"
            rm -rf "/var/www/$KEY"

            echo "${KEY_NAME} | ${USRIP} | ${_key} | ${USED_TIME}" \
                >> /etc/gerar-sh-log

            echo "${KEY_NAME} | ${USRIP} | ${_key} | ${USED_TIME}" \
                >> "${onliCHECK}/checkIP.log"

            chmod +x "${onliCHECK}/checkIP.log"
            ID="$(echo "$KEY_NAME" | awk '{print $1}' | sed 's/[^0-9]//g')"

            if [[ -e /etc/ADM-db/token ]]; then

                TOKEN="$(cat /etc/ADM-db/token)"

                NOTIFY_ID="$ID"

                [[ -z "$NOTIFY_ID" ]] && \
                    NOTIFY_ID="$(cat /etc/ADM-db/Admin-ID 2>/dev/null)"

                if [[ -n "$TOKEN" && -n "$NOTIFY_ID" ]]; then

                    URLBOT="https://api.telegram.org/bot${TOKEN}/sendMessage"

                    MENSAJE="===============================%0A"
                    MENSAJE+="✅ KEY USADA - HEXGEN%0A"
                    MENSAJE+="===============================%0A"
                    MENSAJE+="🔑 KEY: <code>${_key}</code>%0A"
                    MENSAJE+="🌐 IP: <code>${USRIP}</code>%0A"
                    MENSAJE+="⏰ FECHA: ${USED_TIME}%0A"
                    MENSAJE+="===============================%0A"
                    MENSAJE+="⚡ HexGen by JotchuaDevz"
                    MENSAJE+="==============================="

                    curl -s --max-time 10 \
                        -X POST "$URLBOT" \
                        -d "chat_id=${NOTIFY_ID}" \
                        -d "text=${MENSAJE}" \
                        >/dev/null 2>&1
                fi
            fi

            rm -rf "$FILE2"
            rm -f "${FILE2}.name"
            [[ -n "$ID" ]] && echo "$ID" >> "$IVAR"

        ) >/dev/null 2>&1 &
    fi
}

case "$1" in
    -start|-Start|-s|-S|-iniciar|-Iniciar)
        listen_fun
        exit
        ;;
    -install|-Install|-i|-I|-instalar|-Instalar)
        install_fun
        exit
        ;;
    *)
        server_fun
        ;;
esac