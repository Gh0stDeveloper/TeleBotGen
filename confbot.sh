#!/usr/bin/env bash
# TeleBotGen installer and configuration menu.
set -Eeuo pipefail
umask 077

CIDdir="${TELEBOTGEN_STATE_DIR:-/etc/ADM-db}"
SRC="$CIDdir/sources"
REPOSITORY="${TELEBOTGEN_REPOSITORY:-Gh0stDeveloper/TeleBotGen}"
REF="${TELEBOTGEN_REF:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/${REF}"
BAR='============================================================'

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || {
        echo 'ERROR: ejecuta la configuración del bot como root.' >&2
        return 1
    }
}

pause_menu() {
    read -r -p 'Presiona Enter para continuar...' _
}

save_repository_config() {
    install -d -m 700 "$CIDdir"
    cat > "$CIDdir/repository.env" <<EOF
TELEBOTGEN_REPOSITORY=$(printf '%q' "$REPOSITORY")
TELEBOTGEN_REF=$(printf '%q' "$REF")
EOF
    chmod 600 "$CIDdir/repository.env"
}

install_dependencies() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
        bash curl ca-certificates jq socat openssl coreutils iproute2
}

download_file() {
    local url="$1" destination="$2" mode="${3:-700}" tmp
    tmp="$(mktemp "${destination##*/}.XXXXXX")"
    curl -fsSL --retry 3 --connect-timeout 8 --max-time 60 "$url" -o "$tmp" || {
        rm -f "$tmp"
        return 1
    }
    [[ -s "$tmp" ]] || {
        rm -f "$tmp"
        return 1
    }
    sed -i 's/\r$//' "$tmp"
    install -m "$mode" "$tmp" "$destination"
    rm -f "$tmp"
}

install_bot_files() {
    local staging list item destination was_active=0
    require_root
    install_dependencies
    install -d -m 700 "$CIDdir" "$SRC" /etc/http-shell
    save_repository_config

    systemctl is-active --quiet telebotgen.service && was_active=1 || true
    systemctl stop telebotgen.service 2>/dev/null || true

    staging="$(mktemp -d /tmp/telebotgen-update.XXXXXX)"
    trap 'rm -rf "${staging:-}"' RETURN
    list="$staging/lista-bot"
    download_file "$RAW_BASE/sources/lista-bot" "$list" 600 || {
        echo 'ERROR: no se pudo descargar sources/lista-bot.' >&2
        return 1
    }

    while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        [[ "$item" =~ ^[A-Za-z0-9._-]+$ ]] || {
            echo "ERROR: nombre de archivo inválido en lista-bot: $item" >&2
            return 1
        }
        download_file "$RAW_BASE/sources/$item" "$staging/$item" 700 || {
            echo "ERROR: no se pudo descargar $item." >&2
            return 1
        }
    done < "$list"

    for item in "$staging"/*; do
        [[ "${item##*/}" == lista-bot ]] && continue
        if [[ "${item##*/}" == BotGen.sh ]]; then
            destination="$CIDdir/BotGen.sh"
        else
            destination="$SRC/${item##*/}"
        fi
        install -m 700 "$item" "$destination"
    done

    download_file "$RAW_BASE/ShellBot.sh" /bin/ShellBot.sh 700
    download_file "$RAW_BASE/http-server.sh" /usr/local/bin/hexgen-http-server 700
    download_file "$RAW_BASE/update.sh" /usr/local/bin/telebotgen-update 700
    curl -fsSL --retry 2 "$RAW_BASE/Vercion" -o "$CIDdir/vercion" || printf 'desarrollo\n' > "$CIDdir/vercion"
    chmod 600 "$CIDdir/vercion"

    create_services
    if ((was_active == 1)); then
        systemctl restart telebotgen.service
    fi
    echo 'Archivos de TeleBotGen instalados o actualizados correctamente.'
}

create_services() {
    cat > /etc/systemd/system/hexgen-http.service <<'EOF'
[Unit]
Description=TeleBotGen one-time Hex Tunnel key validation
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hexgen-http-server --serve
Restart=on-failure
RestartSec=3s
User=root
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/telebotgen.service <<'EOF'
[Unit]
Description=TeleBotGen Telegram administration bot
After=network-online.target hexgen-http.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/bash /etc/ADM-db/BotGen.sh
Restart=on-failure
RestartSec=5s
User=root
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable hexgen-http.service telebotgen.service >/dev/null 2>&1
    systemctl restart hexgen-http.service
}

configure_token() {
    local token
    clear
    printf '%s\nToken del bot creado con @BotFather\n%s\n' "$BAR" "$BAR"
    read -r -s -p 'TOKEN: ' token
    printf '\n'
    [[ "$token" =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{30,}$ ]] || {
        echo 'Token inválido; no se guardó.'
        pause_menu
        return
    }
    printf '%s\n' "$token" > "$CIDdir/token"
    chmod 600 "$CIDdir/token"
    echo 'Token guardado.'
    pause_menu
}

configure_admin() {
    local admin_id
    clear
    printf '%s\nID numérico del administrador de Telegram\n%s\n' "$BAR" "$BAR"
    read -r -p 'ID: ' admin_id
    [[ "$admin_id" =~ ^[0-9]+$ ]] || {
        echo 'ID inválido; no se guardó.'
        pause_menu
        return
    }
    printf '%s\n' "$admin_id" > "$CIDdir/Admin-ID"
    chmod 600 "$CIDdir/Admin-ID"
    echo 'Administrador guardado.'
    pause_menu
}

configure_public_host() {
    local host
    clear
    printf '%s\nHost público del servidor de keys\n%s\n' "$BAR" "$BAR"
    echo 'Usa la IP pública o un dominio que apunte a este VPS.'
    read -r -p 'HOST: ' host
    [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || {
        echo 'Host inválido; no se guardó.'
        pause_menu
        return
    }
    printf '%s\n' "$host" > "$CIDdir/public-host"
    chmod 600 "$CIDdir/public-host"
    systemctl restart hexgen-http.service 2>/dev/null || true
    echo 'Host público guardado.'
    pause_menu
}

toggle_service() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        systemctl stop "$service"
        echo "$service detenido."
    else
        systemctl start "$service"
        sleep 1
        systemctl is-active --quiet "$service" \
            && echo "$service iniciado." \
            || echo "No se pudo iniciar $service."
    fi
    pause_menu
}

send_test_message() {
    local token admin_id response
    token="$(tr -d '\r\n' < "$CIDdir/token" 2>/dev/null || true)"
    admin_id="$(tr -d '\r\n' < "$CIDdir/Admin-ID" 2>/dev/null || true)"
    [[ -n "$token" && "$admin_id" =~ ^[0-9]+$ ]] || {
        echo 'Configura primero el token y el ID administrador.'
        pause_menu
        return
    }
    response="$(curl -fsS --max-time 10 -X POST \
        "https://api.telegram.org/bot${token}/sendMessage" \
        --data-urlencode "chat_id=$admin_id" \
        --data-urlencode 'text=TeleBotGen está configurado correctamente.' 2>/dev/null || true)"
    grep -q '"ok":true' <<< "$response" \
        && echo 'Mensaje enviado correctamente.' \
        || echo 'Telegram rechazó el mensaje; revisa token e ID.'
    pause_menu
}

show_status() {
    clear
    printf '%s\nESTADO TELEBOTGEN\n%s\n' "$BAR" "$BAR"
    systemctl --no-pager --full status telebotgen.service hexgen-http.service 2>/dev/null || true
    printf '\nPuerto de validación:\n'
    ss -lntp 2>/dev/null | grep -E ":${HEXGEN_PORT:-8888}[[:space:]]" || echo 'No está escuchando.'
    pause_menu
}

bot_gen() {
    local option bot_state server_state version
    while true; do
        clear
        systemctl is-active --quiet telebotgen.service && bot_state='ONLINE' || bot_state='OFFLINE'
        systemctl is-active --quiet hexgen-http.service && server_state='ONLINE' || server_state='OFFLINE'
        version="$(cat "$CIDdir/vercion" 2>/dev/null || printf desarrollo)"
        printf '%s\n' "$BAR"
        printf ' TELEBOTGEN / HEX TUNNEL  %s\n' "$version"
        printf '%s\n' "$BAR"
        printf '[1] Configurar token de Telegram\n'
        printf '[2] Configurar ID administrador\n'
        printf '[3] Configurar host público de keys\n'
        printf '[4] Instalar o actualizar archivos\n'
        printf '[5] Iniciar/detener bot             %s\n' "$bot_state"
        printf '[6] Iniciar/detener servidor keys   %s\n' "$server_state"
        printf '[7] Enviar mensaje de prueba\n'
        printf '[8] Mostrar estado y diagnósticos\n'
        printf '[0] Volver\n'
        printf '%s\n' "$BAR"
        read -r -p 'Opción: ' option
        case "$option" in
            1) configure_token ;;
            2) configure_admin ;;
            3) configure_public_host ;;
            4) install_bot_files; pause_menu ;;
            5) toggle_service telebotgen.service ;;
            6) toggle_service hexgen-http.service ;;
            7) send_test_message ;;
            8) show_status ;;
            0) return 0 ;;
            *) echo 'Opción inválida.'; sleep 1 ;;
        esac
    done
}

bot_conf() {
    require_root
    install -d -m 700 "$CIDdir" "$SRC" /etc/http-shell
    save_repository_config
    if [[ ! -s "$CIDdir/BotGen.sh" || ! -s /usr/local/bin/hexgen-http-server ]]; then
        install_bot_files
    else
        create_services
    fi
    bot_gen
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    bot_conf
fi
