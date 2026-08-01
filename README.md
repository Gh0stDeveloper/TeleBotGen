# TeleBotGen para Hex Tunnel

TeleBotGen administra por Telegram las licencias comerciales de Hex Tunnel mediante `GhostDeveloperLicenseServer`.

Versión: `3.0.0-rc.1`

## Arquitectura

```text
TeleBotGen
  └── http://127.0.0.1:8080/api/v1/admin/
          └── GhostDeveloperLicenseServer
                  ├── autorización HTTPS firmada
                  ├── activaciones vinculadas a IP
                  ├── leases renovables
                  └── descargas privadas de un solo uso
```

El bot y la API se ejecutan en la misma VPS. Los endpoints administrativos no se publican en Internet y el antiguo servidor `HexGen` del puerto `8888` queda desactivado.

## Requisitos

- `GhostDeveloperLicenseServer` instalado y activo en `127.0.0.1:8080`.
- Token administrativo en `/etc/ghostdeveloper-license/secrets/admin-token`.
- Debian 12, Ubuntu 22.04 o Ubuntu 24.04 para la VPS del bot.
- Token de Telegram creado mediante `@BotFather`.

Hex Tunnel debe instalarse en una VPS distinta, dedicada y con arquitectura amd64/x86_64. No debe instalarse en la VPS del bot, de la API o de una web crítica.

## Instalación de la rama RC

```bash
curl -fsSL "https://raw.githubusercontent.com/Gh0stDeveloper/TeleBotGen/feat/hextunnel-license-integration/confbot.sh" \
  -o /tmp/telebotgen-conf.sh && \
TELEBOTGEN_REF=feat/hextunnel-license-integration sudo -E bash /tmp/telebotgen-conf.sh
```

Después de fusionar el PR, el instalador estable utilizará `main`.

El configurador permite guardar el token, definir el administrador inicial, agregar revendedores, autorizar grupos, instalar archivos, controlar el servicio y verificar la API.

## Roles

### Administrador

Puede generar y administrar licencias, revendedores, grupos permitidos y diagnósticos.

### Revendedor

Puede emitir licencias para clientes y consultar las licencias que él mismo creó. Por defecto, una licencia de revendedor no puede superar 43,200 minutos.

### Cliente

El bot identifica al cliente mediante `owner_telegram_id` en la API. `/start` muestra únicamente su estado, vencimiento, IP vinculada y tiempo restante, sin exponer funciones administrativas.

### Público

Puede consultar su ID, la página oficial y los desarrolladores, pero no generar licencias.

## Grupos permitidos

TeleBotGen procesa comandos administrativos en grupos únicamente cuando el ID negativo del grupo está registrado en:

```text
/etc/ADM-db/Allowed-Groups
```

Un administrador puede ejecutar `/allowgroup` dentro del grupo para autorizarlo. Las keys generadas desde grupos se envían por privado al administrador o revendedor que ejecutó el comando; el grupo recibe solo una confirmación.

## Comandos

Comunes:

```text
/start
/menu
/id
/help
/license
/install
/upgrade
```

Revendedor:

```text
/keygen [minutos] [telegram_id] [usuario]
/mykeys
```

Administrador:

```text
/keygen [minutos] [telegram_id] [usuario]
/licenses [telegram_id]
/revoke license_id [motivo]
/reset license_id [motivo]
/addreseller telegram_id
/delreseller telegram_id
/resellers
/allowgroup [chat_id]
/delgroup [chat_id]
/groups
/api
/infosys
/update
```

También se puede responder al mensaje de un cliente y ejecutar `/keygen minutos` para usar automáticamente su ID.

## Instalador entregado al cliente

El bot entrega un comando que:

1. instala `curl` y certificados cuando faltan;
2. descarga `https://ghostdeveloper.duckdns.org/install.sh`;
3. solicita la key;
4. verifica la autorización RSA;
5. valida la integridad SHA-256;
6. descarga el paquete privado temporal;
7. ejecuta Hex Tunnel.

Después de instalar:

```bash
sudo hextunnel-license status
sudo hextunnel-upgrade
```

## Archivos persistentes

```text
/etc/ADM-db/token
/etc/ADM-db/Admin-ID
/etc/ADM-db/Reseller-ID
/etc/ADM-db/Allowed-Groups
/etc/ADM-db/repository.env
```

Los archivos privados usan permisos `600`; el directorio de estado utiliza `700`.

## Diagnóstico

```bash
systemctl status telebotgen.service ghost-license-api.service --no-pager
journalctl -u telebotgen.service -n 100 --no-pager
curl -sS http://127.0.0.1:8080/health | jq
ss -lntp | grep -E ':(8080|8888)\b'
```

La API debe escuchar solamente en `127.0.0.1:8080` y no debe existir ningún listener en `8888`.

## Desarrolladores

- `@Gh0stDeveloper`: integración, licencias e infraestructura.
- `@Jotchua_DevzZ`: proyecto original y desarrollo base.
