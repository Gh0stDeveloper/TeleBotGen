#!/bin/bash
SCPresq="aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL0pvdGNodWFEZXZ6L1RlbGVCb3RHZW4vbWFzdGVyL3NvdXJjZXM="
SUB_DOM='base64 -d'
bar="\e[0;36m=====================================================\e[0m"
CIDdir=/etc/ADM-db

check_ip () {
MIP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
MIP2=$(wget -qO- ipv4.icanhazip.com)
[[ "$MIP" != "$MIP2" ]] && IP="$MIP2" || IP="$MIP"
[[ ! -d "${CIDdir}" ]] && mkdir -p "${CIDdir}"
echo "$IP" > "${CIDdir}/vendor_code"
}

function_verify () {
v1=$(curl -sSL "https://raw.githubusercontent.com/JotchuaDevz/TeleBotGen/master/Vercion")
echo "$v1" > "${CIDdir}/vercion"
}

veryfy_fun () {
    SRC="${CIDdir}/sources"
    mkdir -p "$SRC"

    case "$1" in
        "BotGen.sh")
            ARQ="${CIDdir}"
            ;;
        "http-server.sh")
            ARQ="/usr/local/bin"
            ;;
        *)
            ARQ="${SRC}"
            ;;
    esac

    mv -f "$HOME/$1" "${ARQ}/$1"
    chmod +x "${ARQ}/$1"

    if [[ "$1" == "http-server.sh" ]]; then
        mv -f "${ARQ}/http-server.sh" "${ARQ}/hexgen-http-server"
        chmod +x "${ARQ}/hexgen-http-server"
    fi
}

download () {
clear
echo -e "$bar"
echo -e "\033[1;33mDescargando archivos... "
echo -e "$bar"
cd "$HOME" || return 1
REQUEST=$(echo "$SCPresq" | $SUB_DOM)

wget -q -O "$HOME/HexGen" "${REQUEST}/lista-bot"

if [[ ! -s "$HOME/HexGen" ]]; then
    echo -e "\033[1;31m❌ No se pudo descargar la lista de archivos."
    echo -e "   Revisa tu conexión a internet o que el repositorio\n   este disponible, e intenta de nuevo.\033[0m"
    echo -e "$bar"
    rm -f "$HOME/HexGen"
    read -r foo
    return 1
fi

fallo_total=0
while IFS= read -r arqx; do
    [[ -z "$arqx" ]] && continue
    echo -ne "\033[1;33mDescargando: \033[1;31m[$arqx] "
    wget -q -O "$HOME/$arqx" "${REQUEST}/${arqx}"
    if [[ -s "$HOME/$arqx" ]]; then
        echo -e "\033[1;31m- \033[1;32mRecibido!"
        veryfy_fun "$arqx"
    else
        echo -e "\033[1;31m- \033[1;31mFalla (no recibido!)"
        rm -f "$HOME/$arqx"
        fallo_total=1
    fi
done < "$HOME/HexGen"

rm -f "$HOME/HexGen"

if [[ $fallo_total -eq 1 ]]; then
    echo -e "$bar"
    echo -e "\033[1;31m⚠️  Algunos archivos no se descargaron correctamente.\033[0m"
    echo -e "$bar"
    read -r foo
fi
}

ini_token () {
clear
echo -e "$bar"
echo -e "  \033[1;37mIngrese el token de su bot"
echo -e "$bar"
echo -n "TOKEN: "
read -r opcion

if [[ -z "$opcion" ]]; then
    echo -e "$bar"
    echo -e "  \033[1;31m❌ No ingresaste ningun token, no se guardo nada."
    echo -e "$bar"
    read -r foo
    bot_gen
    return
fi

echo "$opcion" > "${CIDdir}/token"
echo -e "$bar"
echo -e "  \033[1;32mtoken se guardo con exito!" && echo -e "$bar" && echo -e "  \033[1;37mPara tener acceso a todos los comandos del bot\n  deve iniciar el bot en la opcion 2.\n  desde su apps (telegram). ingresar al bot!\n  digite el comando \033[1;31m/id\n  \033[1;37mel bot le respodera con su ID de telegram.\n  copiar el ID e ingresar el mismo en la opcion 3" && echo -e "$bar"
read -r foo
bot_gen
}

ini_id () {
clear
echo -e "$bar"
echo -e "  \033[1;37mIngrese su ID de telegram"
echo -e "$bar"
echo -n "ID: "
read -r opcion

if [[ -z "$opcion" || ! "$opcion" =~ ^[0-9]+$ ]]; then
    echo -e "$bar"
    echo -e "  \033[1;31m❌ ID invalido, deve ser solo numeros."
    echo -e "$bar"
    read -r foo
    bot_gen
    return
fi

echo "$opcion" > "${CIDdir}/Admin-ID"
echo -e "$bar"
echo -e "  \033[1;32mID guardo con exito!" && echo -e "$bar" && echo -e "  \033[1;37mdesde su apps (telegram). ingresar al bot!\n  digite el comando \033[1;31m/menu\n  \033[1;37mprueve si tiene acceso al menu extendido." && echo -e "$bar"
read -r foo
bot_gen
}

instalar_servicios() {
    mkdir -p /etc/http-shell
    mkdir -p "$CIDdir"

    apt-get update -qq
    # FIX: http-server.sh ya no usa netcat-traditional (nc solo atiende una
    # conexion a la vez y se cuelga con clientes que no mandan datos). Ahora
    # usa socat con 'fork', que si soporta multiples conexiones en paralelo.
    if ! apt-get install -y jq socat bc python3 at; then
        echo -e "\033[1;31m⚠️  Algun paquete no se pudo instalar, revisa arriba cual fallo.\033[0m"
        read -r foo
    fi
    systemctl enable atd >/dev/null 2>&1
    systemctl start atd >/dev/null 2>&1

    NEEDS_RELOAD=0
    if [[ ! -f "/usr/local/bin/hexgen-http-server" ]]; then
        wget -q -O "/usr/local/bin/hexgen-http-server" \
            "https://raw.githubusercontent.com/JotchuaDevz/TeleBotGen/master/http-server.sh"

      if [[ -s "/usr/local/bin/hexgen-http-server" ]]; then
    chmod +x "/usr/local/bin/hexgen-http-server"
    sed -i 's|PROGRAMA="/bin/http-server.sh"|PROGRAMA="/usr/local/bin/hexgen-http-server"|' \
        "/usr/local/bin/hexgen-http-server"
else
            rm -f "/usr/local/bin/hexgen-http-server"
        fi
    fi

    if [[ -f "/usr/local/bin/hexgen-http-server" ]]; then
        chmod +x "/usr/local/bin/hexgen-http-server"

        if [[ ! -f /etc/systemd/system/hexgen-http.service ]]; then
            cat > /etc/systemd/system/hexgen-http.service <<EOF
[Unit]
Description=HexGen HTTP Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hexgen-http-server -start
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
            NEEDS_RELOAD=1
        fi
    else
        echo -e "\033[1;31m⚠️  No se pudo descargar hexgen-http-server, se omite ese servicio.\033[0m"
        read -r foo
    fi

    if [[ -f "${CIDdir}/BotGen.sh" ]]; then
        chmod +x "${CIDdir}/BotGen.sh"

        if [[ ! -f /etc/systemd/system/telebotgen.service ]]; then
            cat > /etc/systemd/system/telebotgen.service <<EOF
[Unit]
Description=HexGen Telegram Bot
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash ${CIDdir}/BotGen.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
            NEEDS_RELOAD=1
        fi
    else
        echo -e "\033[1;31m⚠️  No existe ${CIDdir}/BotGen.sh, se omite ese servicio.\033[0m"
        read -r foo
    fi

    if [[ $NEEDS_RELOAD -eq 1 ]]; then
        systemctl daemon-reload
        [[ -f /etc/systemd/system/hexgen-http.service ]] && systemctl enable hexgen-http.service >/dev/null 2>&1
        [[ -f /etc/systemd/system/telebotgen.service ]] && systemctl enable telebotgen.service >/dev/null 2>&1
    fi

    if [[ -f /etc/systemd/system/hexgen-http.service ]] && ! systemctl is-active --quiet hexgen-http.service; then
        systemctl restart hexgen-http.service
    fi

    echo -e "\033[1;32m✅ Instalacion de servicios finalizada.\033[0m"
    read -r foo
}

start_bot() {
    [[ ! -e "$CIDdir/token" ]] && echo "null" > "$CIDdir/token"
    if [[ ! -f /etc/systemd/system/telebotgen.service ]]; then
        clear
        echo -e "$bar"
        echo -e "\033[1;31m❌ El servicio telebotgen.service aun no esta instalado."
        echo -e "   Sal al menu principal y vuelve a entrar a esta opcion"
        echo -e "   para que se reintente la instalacion de servicios."
        echo -e "$bar"
        read -r foo
        bot_gen
        return
    fi

    if systemctl is-active --quiet telebotgen.service; then
        systemctl stop telebotgen.service

        clear
        echo -e "$bar"
        echo -e "\033[1;31m            BotGen fuera de linea"
        echo -e "$bar"

        sleep 3
    else
        TOKEN="$(cat "$CIDdir/token" 2>/dev/null)"

        if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
            clear
            echo -e "$bar"
            echo -e "\033[1;31m❌ No has ingresado el token del bot todavia."
            echo -e "   Ve a la opcion [1] primero."
            echo -e "$bar"

            read -r foo
            bot_gen
            return
        fi

        chmod +x "$CIDdir/BotGen.sh"

        systemctl daemon-reload
        systemctl start telebotgen.service

        sleep 2

        if systemctl is-active --quiet telebotgen.service; then
            clear
            echo -e "$bar"
            echo -e "\033[1;32m                BotGen en linea"
            echo -e "$bar"
            sleep 3
        else
            clear
            echo -e "$bar"
            echo -e "\033[1;31m❌ El bot no pudo iniciar."
            echo -e "$bar"
            echo
            systemctl status telebotgen.service --no-pager
            echo
            read -r foo
        fi
    fi

    bot_gen
}

ayuda_fun () {
clear
echo -e "$bar"
echo -e "            \e[47m\e[30m Instrucciones rapidas \e[0m"
echo -e "$bar"
echo -e "\033[1;37m   Es necesario crear un bot en \033[1;32m@BotFather "
echo -e "$bar"
echo -e "\033[1;32m1- \033[1;37mEn su apps telegram ingrese a @BotFather"
echo -e "\033[1;32m2- \033[1;37mDigite el comando \033[1;31m/newbot"
echo -e "\033[1;32m3- @BotFather \033[1;37msolicitara que\n   asigne un nombre a su bot"
echo -e "\033[1;32m4- @BotFather \033[1;37msolicitara que asigne otro nombre,\n   esta vez deve finalizar en bot eje: \033[1;31mXXX_bot"
echo -e "\033[1;32m5- \033[1;37mObtener token del bot creado.\n   En \033[1;32m@BotFather \033[1;37mdigite el comando \033[1;31m/token\n   \033[1;37mseleccione el bot y copie el token."
echo -e "\033[1;32m6- \033[1;37mIngrese el token\n   en la opcion \033[1;32m[1] \033[1;31m> \033[1;37mTOKEN DEL BOT"
echo -e "\033[1;32m7- \033[1;37mPoner en linea el bot\n   en la opcion \033[1;32m[2] \033[1;31m> \033[1;37mINICIAR/PARAR BOT"
echo -e "\033[1;32m8- \033[1;37mEn su apps telegram, inicie el bot creado\n   digite el comando \033[1;31m/id \033[1;37mel bot le respondera\n   con su ID de telegran (copie el ID)"
echo -e "\033[1;32m9- \033[1;37mIngrese el ID en la\n   opcion \033[1;32m[3] \033[1;31m> \033[1;37mID DE USUARIO TELEGRAM"
echo -e "\033[1;32m10-\033[1;37mcomprueve que tiene acceso a\n   las opciones avanzadas de su bot."
echo -e "$bar"
read -r foo
bot_gen
}

bot_conf () {
[[ ! -d "${CIDdir}" ]] && mkdir -p "${CIDdir}"
check_ip
function_verify
[[ ! -f "${CIDdir}/BotGen.sh" ]] && download
instalar_servicios
bot_gen
}

msj_prueba () {
TOKEN="$(cat "${CIDdir}/token" 2>/dev/null)"
ID="$(cat "${CIDdir}/Admin-ID" 2>/dev/null)"

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
    clear
    echo -e "$bar"
    echo -e "\033[1;37m Aun no a ingresado el token\n No se puede enviar ningun mensaje!"
    echo -e "$bar"
    read -r foo
elif [[ -z "$ID" ]]; then
    clear
    echo -e "$bar"
    echo -e "\033[1;37m Aun no a ingresado el ID\n No se puede enviar ningun mensaje!"
    echo -e "$bar"
    read -r foo
else
    MENSAJE="Esto es un mesaje de prueba!"
    URL="https://api.telegram.org/bot$TOKEN/sendMessage"
    RESP=$(curl -s -X POST "$URL" -d chat_id="$ID" -d text="$MENSAJE")
    clear
    echo -e "$bar"
    if echo "$RESP" | grep -q '"ok":true'; then
        echo -e "\033[1;32m mensaje enviado...!"
    else
        echo -e "\033[1;31m❌ fallo el envio, revisa token/ID."
    fi
    echo -e "$bar"
    sleep 2
fi
bot_gen
}

bot_gen () {
clear
unset PID_GEN

if systemctl is-active --quiet telebotgen.service; then
    PID_GEN="\033[1;32monline"
else
    PID_GEN="\033[1;31moffline"
fi

[[ ! -d "${CIDdir}" ]] && mkdir -p "${CIDdir}"
echo -e "$bar"
echo -e "     \e[47m \e[30m>>>>>>  BotGen by \e[1;36mJotchuaDevzZ\e[1;32m  $(cat "${CIDdir}/vercion" 2>/dev/null)\e[0m\e[47m \e[30m<<<<<< \e[0m"
echo -e "$bar"
echo -e "\033[1;32m[1] \033[1;36m> \033[1;37mTOKEN DEL BOT"
echo -e "\033[1;32m[2] \033[1;36m> \033[1;37mINICIAR/PARAR BOT $PID_GEN\033[0m"
echo -e "\033[1;32m[3] \033[1;36m> \033[1;37mID DE USUARIO TELEGRAM"
echo -e "\033[1;32m[4] \033[1;36m> \033[1;37mMENSAJE DE PRUEBA"
echo -e "\033[1;32m[5] \033[1;36m> \033[1;37mMANUAL"
echo -e "$bar"
echo -e "\e[1;32m[0] \e[36m>\e[0m \e[47m\e[30m <<ATRAS "
echo -e "$bar"
echo -n "Opcion: "
read -r opcion
case "$opcion" in
0) ;;
1) ini_token;;
2) start_bot;;
3) ini_id;;
4) msj_prueba;;
5) ayuda_fun;;
*)
   echo -e "\033[1;31mOpcion invalida."
   sleep 1
   bot_gen
   ;;
esac
}
