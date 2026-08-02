#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STATE_DIR="${TELEBOTGEN_STATE_DIR:-/etc/ADM-db}"
SOURCES_DIR="$STATE_DIR/sources"
BACKUP_ROOT="${TELEBOTGEN_BACKUP_ROOT:-/var/backups/telebotgen}"
REPOSITORY="${TELEBOTGEN_REPOSITORY:-Gh0stDeveloper/TeleBotGen}"
REF="${TELEBOTGEN_REF:-feat/hextunnel-license-integration}"
SOURCE_ROOT="${TELEBOTGEN_SOURCE_ROOT:-}"
RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/${REF}"
LICENSE_HEALTH="${TELEBOTGEN_LICENSE_HEALTH:-http://127.0.0.1:8080/health}"
LOCK_FILE=/run/lock/telebotgen-deploy.lock
SERVICE_USER=telebotgen
SERVICE_GROUP=telebotgen
LICENSE_GROUP=ghostlicense

log() { printf '[telebotgen-deploy] %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || fail 'ejecuta como root.'; }

install_dependencies() {
    local missing=0 command
    for command in bash curl jq openssl systemctl runuser; do
        command -v "$command" >/dev/null 2>&1 || missing=1
    done
    ((missing == 0)) && return 0
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
        bash curl ca-certificates jq openssl coreutils iproute2 util-linux
}

prepare_identity() {
    getent group "$LICENSE_GROUP" >/dev/null \
        || fail "falta el grupo $LICENSE_GROUP; instala primero GhostDeveloperLicenseServer."
    getent group "$SERVICE_GROUP" >/dev/null \
        || groupadd --system "$SERVICE_GROUP"
    if ! id "$SERVICE_USER" >/dev/null 2>&1; then
        useradd --system \
            --gid "$SERVICE_GROUP" \
            --groups "$LICENSE_GROUP" \
            --home-dir /nonexistent \
            --shell /usr/sbin/nologin \
            "$SERVICE_USER"
    else
        usermod -a -G "$LICENSE_GROUP" "$SERVICE_USER"
    fi
}

prepare_state() {
    local duration
    install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 700 "$STATE_DIR" "$SOURCES_DIR"
    install -d -o root -g root -m 700 "$BACKUP_ROOT"
    for file in Admin-ID Reseller-ID Allowed-Groups; do
        [[ -e "$STATE_DIR/$file" ]] || : > "$STATE_DIR/$file"
        chown "$SERVICE_USER:$SERVICE_GROUP" "$STATE_DIR/$file"
        chmod 600 "$STATE_DIR/$file"
    done
    duration="$(tr -d '[:space:]' < "$STATE_DIR/Key-Duration-Minutes" 2>/dev/null || true)"
    if [[ ! "$duration" =~ ^[0-9]+$ || "$duration" -lt 1 || "$duration" -gt 525600 ]]; then
        printf '240\n' > "$STATE_DIR/Key-Duration-Minutes"
    fi
    chown "$SERVICE_USER:$SERVICE_GROUP" "$STATE_DIR/Key-Duration-Minutes"
    chmod 600 "$STATE_DIR/Key-Duration-Minutes"
    cat > "$STATE_DIR/repository.env" <<EOF
TELEBOTGEN_REPOSITORY=$(printf '%q' "$REPOSITORY")
TELEBOTGEN_REF=$(printf '%q' "$REF")
EOF
    chown "$SERVICE_USER:$SERVICE_GROUP" "$STATE_DIR/repository.env"
    chmod 600 "$STATE_DIR/repository.env"
    if [[ -e "$STATE_DIR/token" ]]; then
        chown "$SERVICE_USER:$SERVICE_GROUP" "$STATE_DIR/token"
        chmod 600 "$STATE_DIR/token"
    fi
}

fetch_file() {
    local relative="$1" destination="$2"
    if [[ -n "$SOURCE_ROOT" && -f "$SOURCE_ROOT/$relative" ]]; then
        install -m 600 "$SOURCE_ROOT/$relative" "$destination"
    else
        curl -fsSL --retry 3 --connect-timeout 8 --max-time 60 \
            "$RAW_BASE/$relative" -o "$destination"
        chmod 600 "$destination"
    fi
    sed -i 's/\r$//' "$destination"
    [[ -s "$destination" ]] || fail "archivo vacío: $relative"
}

write_units() {
    rm -f "$STATE_DIR/update.request"

    cat > /etc/systemd/system/telebotgen.service <<EOF
[Unit]
Description=TeleBotGen - administración de licencias Hex Tunnel
After=network-online.target ghost-license-api.service
Wants=network-online.target ghost-license-api.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
SupplementaryGroups=$LICENSE_GROUP
WorkingDirectory=$STATE_DIR
ExecStart=/usr/bin/bash $STATE_DIR/BotGen.sh
Restart=on-failure
RestartSec=5s
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
LockPersonality=true
RestrictSUIDSGID=true
RestrictRealtime=true
RestrictNamespaces=true
SystemCallArchitectures=native
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
CapabilityBoundingSet=
AmbientCapabilities=
ReadOnlyPaths=/bin/ShellBot.sh /etc/ghostdeveloper-license
ReadWritePaths=$STATE_DIR

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/telebotgen-update.service <<EOF
[Unit]
Description=Actualizar TeleBotGen mediante un comando fijo
After=network-online.target ghost-license-api.service
Wants=network-online.target ghost-license-api.service

[Service]
Type=oneshot
User=root
UMask=0077
ExecStart=/usr/local/bin/telebotgen-update
ExecStartPost=/usr/bin/rm -f $STATE_DIR/update.request
TimeoutStartSec=15min
EOF

    cat > /etc/systemd/system/telebotgen-update.path <<EOF
[Unit]
Description=Procesar solicitudes seguras de actualización de TeleBotGen

[Path]
PathExists=$STATE_DIR/update.request
Unit=telebotgen-update.service

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 \
        /etc/systemd/system/telebotgen.service \
        /etc/systemd/system/telebotgen-update.service \
        /etc/systemd/system/telebotgen-update.path
    systemctl daemon-reload
    systemctl enable telebotgen.service telebotgen-update.path >/dev/null
    systemctl restart telebotgen-update.path
}

restore_backup() {
    local backup="$1" destination source_name mapping
    log "Restaurando $backup"
    systemctl stop telebotgen.service telebotgen-update.path >/dev/null 2>&1 || true
    rm -rf "$SOURCES_DIR"
    if [[ -d "$backup/sources" ]]; then
        cp -a "$backup/sources" "$SOURCES_DIR"
    else
        install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 700 "$SOURCES_DIR"
    fi
    for mapping in \
        'BotGen.sh:state-BotGen.sh:700' \
        'vercion:state-vercion:600' \
        '/bin/ShellBot.sh:bin-ShellBot.sh:755' \
        '/usr/local/bin/telebotgen-update:bin-telebotgen-update:700' \
        '/usr/local/bin/telebotgen-deploy:bin-telebotgen-deploy:700' \
        '/etc/systemd/system/telebotgen.service:service:644' \
        '/etc/systemd/system/telebotgen-update.service:update-service:644' \
        '/etc/systemd/system/telebotgen-update.path:update-path:644'; do
        destination="${mapping%%:*}"
        rest="${mapping#*:}"
        source_name="${rest%%:*}"
        mode="${rest##*:}"
        [[ "$destination" == /* ]] || destination="$STATE_DIR/$destination"
        if [[ -f "$backup/$source_name" ]]; then
            install -m "$mode" "$backup/$source_name" "$destination"
        else
            rm -f "$destination"
        fi
    done
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$STATE_DIR"
    chmod 700 "$STATE_DIR" "$SOURCES_DIR"
    find "$SOURCES_DIR" -type f -exec chmod 700 {} + 2>/dev/null || true
    chown root:root /bin/ShellBot.sh /usr/local/bin/telebotgen-update /usr/local/bin/telebotgen-deploy 2>/dev/null || true
    systemctl daemon-reload
    [[ -f /etc/systemd/system/telebotgen-update.path ]] \
        && systemctl enable --now telebotgen-update.path >/dev/null 2>&1 || true
    if [[ -s "$STATE_DIR/token" && -s "$STATE_DIR/Admin-ID" ]]; then
        systemctl restart telebotgen.service || true
    fi
}

main() {
    local staging list item backup timestamp previous_active=0
    require_root
    exec 9>"$LOCK_FILE"
    flock -n 9 || fail 'ya existe otra actualización de TeleBotGen en curso.'
    install_dependencies
    prepare_identity
    prepare_state
    curl -fsS --connect-timeout 3 --max-time 8 "$LICENSE_HEALTH" \
        | jq -e '.status == "online"' >/dev/null \
        || fail 'GhostDeveloperLicenseServer no está operativo.'

    systemctl is-active --quiet telebotgen.service && previous_active=1 || true
    staging="$(mktemp -d /tmp/telebotgen-stage.XXXXXX)"
    trap 'rm -rf "${staging:-}"' EXIT
    install -d -m 700 "$staging/sources"

    fetch_file sources/lista-bot "$staging/lista-bot"
    list="$staging/lista-bot"
    while IFS= read -r item; do
        [[ -n "$item" && "$item" =~ ^[A-Za-z0-9._-]+$ ]] || continue
        fetch_file "sources/$item" "$staging/sources/$item"
        bash -n "$staging/sources/$item"
    done < "$list"
    fetch_file ShellBot.sh "$staging/ShellBot.sh"
    fetch_file update.sh "$staging/update.sh"
    fetch_file deploy.sh "$staging/deploy.sh"
    fetch_file Vercion "$staging/Vercion"
    bash -n "$staging/ShellBot.sh"
    bash -n "$staging/update.sh"
    bash -n "$staging/deploy.sh"
    grep -Eq '^V[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' "$staging/Vercion" \
        || fail 'Vercion contiene un valor inválido.'
    grep -Fq 'ShellBot.getUpdates --limit 100' "$staging/sources/BotGen.sh"
    grep -Fq 'http://127.0.0.1:8080' "$staging/sources/license_api"
    grep -Fq 'update.request' "$staging/sources/update"
    ! grep -Fq 'systemd-run' "$staging/sources/update"

    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    backup="$BACKUP_ROOT/$timestamp"
    install -d -m 700 "$backup"
    [[ -d "$SOURCES_DIR" ]] && cp -a "$SOURCES_DIR" "$backup/sources"
    [[ -f "$STATE_DIR/BotGen.sh" ]] && cp -a "$STATE_DIR/BotGen.sh" "$backup/state-BotGen.sh"
    [[ -f "$STATE_DIR/vercion" ]] && cp -a "$STATE_DIR/vercion" "$backup/state-vercion"
    [[ -f /bin/ShellBot.sh ]] && cp -a /bin/ShellBot.sh "$backup/bin-ShellBot.sh"
    [[ -f /usr/local/bin/telebotgen-update ]] && cp -a /usr/local/bin/telebotgen-update "$backup/bin-telebotgen-update"
    [[ -f /usr/local/bin/telebotgen-deploy ]] && cp -a /usr/local/bin/telebotgen-deploy "$backup/bin-telebotgen-deploy"
    [[ -f /etc/systemd/system/telebotgen.service ]] && cp -a /etc/systemd/system/telebotgen.service "$backup/service"
    [[ -f /etc/systemd/system/telebotgen-update.service ]] && cp -a /etc/systemd/system/telebotgen-update.service "$backup/update-service"
    [[ -f /etc/systemd/system/telebotgen-update.path ]] && cp -a /etc/systemd/system/telebotgen-update.path "$backup/update-path"

    systemctl stop telebotgen.service >/dev/null 2>&1 || true
    systemctl disable --now hexgen-http.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/hexgen-http.service /usr/local/bin/hexgen-http-server

    if ! {
        rm -rf "$STATE_DIR/sources.new"
        cp -a "$staging/sources" "$STATE_DIR/sources.new"
        find "$STATE_DIR/sources.new" -type f -exec chmod 700 {} +
        rm -rf "$SOURCES_DIR.old"
        [[ -d "$SOURCES_DIR" ]] && mv "$SOURCES_DIR" "$SOURCES_DIR.old"
        mv "$STATE_DIR/sources.new" "$SOURCES_DIR"
        install -m 700 "$staging/sources/BotGen.sh" "$STATE_DIR/BotGen.sh.new"
        mv -f "$STATE_DIR/BotGen.sh.new" "$STATE_DIR/BotGen.sh"
        install -m 755 "$staging/ShellBot.sh" /bin/ShellBot.sh.new
        mv -f /bin/ShellBot.sh.new /bin/ShellBot.sh
        install -m 700 "$staging/update.sh" /usr/local/bin/telebotgen-update.new
        mv -f /usr/local/bin/telebotgen-update.new /usr/local/bin/telebotgen-update
        install -m 700 "$staging/deploy.sh" /usr/local/bin/telebotgen-deploy.new
        mv -f /usr/local/bin/telebotgen-deploy.new /usr/local/bin/telebotgen-deploy
        install -m 600 "$staging/Vercion" "$STATE_DIR/vercion"
        chown -R "$SERVICE_USER:$SERVICE_GROUP" "$STATE_DIR"
        chmod 700 "$STATE_DIR" "$SOURCES_DIR" "$STATE_DIR/BotGen.sh"
        find "$SOURCES_DIR" -type f -exec chmod 700 {} +
        chmod 600 "$STATE_DIR/vercion" "$STATE_DIR/repository.env" "$STATE_DIR/Key-Duration-Minutes"
        [[ -f "$STATE_DIR/token" ]] && chmod 600 "$STATE_DIR/token"
        chown root:root /bin/ShellBot.sh /usr/local/bin/telebotgen-update /usr/local/bin/telebotgen-deploy
        write_units
        if [[ -s "$STATE_DIR/token" && -s "$STATE_DIR/Admin-ID" ]]; then
            systemctl restart telebotgen.service
            sleep 2
            systemctl is-active --quiet telebotgen.service
            [[ "$(systemctl show telebotgen.service -p User --value)" == "$SERVICE_USER" ]]
        elif ((previous_active)); then
            false
        fi
    }; then
        restore_backup "$backup"
        fail "actualización revertida; respaldo: $backup"
    fi

    rm -rf "$SOURCES_DIR.old"
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
        | sort -nr | awk 'NR>10{sub(/^[^ ]+ /, ""); print}' \
        | xargs -r rm -rf --
    log "Actualización correcta: $(tr -d '\r\n' < "$STATE_DIR/vercion")"
    systemctl --no-pager --full status telebotgen.service || true
}

main "$@"
