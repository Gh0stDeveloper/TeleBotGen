# TeleBotGen para Hex Tunnel

TeleBotGen administra por Telegram las licencias comerciales de Hex Tunnel mediante `GhostDeveloperLicenseServer`.

Versión: `V3.1.0-rc.1`

## Cambios operativos de 3.1

- Actualización transaccional mediante `deploy.sh`.
- Descarga y validación completa antes de detener el bot.
- Respaldo en `/var/backups/telebotgen`.
- Rollback automático cuando el servicio no vuelve a quedar activo.
- Ejecución del bot como usuario de sistema `telebotgen`, no como root.
- Actualización root mediante una unidad fija activada por `telebotgen-update.path`.
- Procedencia de actualización protegida en `/etc/telebotgen/deploy.env`, propiedad de root y modo `600`.
- Token de Telegram y token administrativo ocultos de los argumentos de `curl`.
- Consulta de licencias por `owner_telegram_id` directamente en la API.
- Prevención de duplicados sin depender de una lista global limitada a 200 registros.
- `confbot.sh install` permite despliegues no interactivos desde `ghostctl` y GitHub Actions.

## Arquitectura

```text
Usuario de Telegram
  └── /Keygen
       └── TeleBotGen obtiene el ID real del remitente
            └── http://127.0.0.1:8080/api/v1/admin/licenses
                 └── GhostDeveloperLicenseServer
                      ├── licencia asociada al Telegram ID
                      ├── autorización HTTPS firmada
                      ├── activación vinculada a IP
                      ├── lease renovable
                      └── descarga privada de un solo uso
```

El bot y la API se ejecutan en la misma VPS. Los endpoints administrativos no se publican y el listener heredado `8888` permanece desactivado.

## Separación de privilegios

`telebotgen.service` usa:

```text
User=telebotgen
SupplementaryGroups=ghostlicense
NoNewPrivileges=true
ProtectSystem=strict
CapabilityBoundingSet=
```

El usuario del bot puede modificar únicamente su estado en `/etc/ADM-db`. Puede leer el token administrativo mediante el grupo `ghostlicense`, pero no puede modificarlo.

El comando `/update` no ejecuta `systemctl`, `systemd-run` ni comandos root. Solo crea:

```text
/etc/ADM-db/update.request
```

`telebotgen-update.path` detecta esa solicitud, la elimina antes de comenzar y ejecuta un actualizador root fijo. El repositorio y la referencia autorizados se leen exclusivamente de:

```text
/etc/telebotgen/deploy.env
```

Ese archivo pertenece a root, usa modo `600` y no es escribible por el bot.

## Requisitos

- GhostDeveloperLicenseServer activo en `127.0.0.1:8080`.
- Token administrativo en `/etc/ghostdeveloper-license/secrets/admin-token`.
- Debian 12, Ubuntu 22.04 o Ubuntu 24.04.
- Token de Telegram generado mediante `@BotFather`.

La VPS cliente de Hex Tunnel debe ser distinta a la VPS del bot y puede usar AMD64 o ARM64.

## Instalación o actualización

### Desde el repositorio

```bash
curl -fsSL "https://raw.githubusercontent.com/Gh0stDeveloper/TeleBotGen/feat/hextunnel-license-integration/confbot.sh" \
  -o /tmp/confbot.sh
sudo TELEBOTGEN_REF=feat/hextunnel-license-integration bash /tmp/confbot.sh install
```

### Desde el servidor de operaciones

```bash
sudo ghostctl deploy-bot
```

### Actualización instalada

```bash
sudo telebotgen-update
```

Los tres métodos usan el mismo despliegue transaccional.

## Configuración interactiva

```bash
sudo bash confbot.sh menu
```

Permite configurar:

- token del bot;
- administrador;
- revendedores;
- grupos permitidos;
- duración global de keys;
- servicio, actualización y diagnósticos.

## Generación de keys

El usuario ejecuta únicamente:

```text
/Keygen
```

TeleBotGen usa `message_from_id` o `callback_query_from_id`. La licencia siempre pertenece al usuario que realizó la acción; no se aceptan ID, username ni duración como argumentos.

## Prevención de duplicados

La API se consulta con:

```text
owner_telegram_id=<ID>&active_only=true
```

La API también protege la creación dentro de una transacción. Aunque dos solicitudes `/Keygen` lleguen simultáneamente, solo una licencia activa puede crearse para el mismo Telegram ID y producto.

## Duración global

```text
/etc/ADM-db/Key-Duration-Minutes
```

Valor predeterminado: `240` minutos.

Comandos:

```text
/Keytime
/Setkeytime 1440
```

## Grupos permitidos

```text
/etc/ADM-db/Allowed-Groups
```

En un grupo autorizado:

- todos los miembros pueden ejecutar `/Keygen`;
- cada miembro genera solo su propia key;
- la key se envía por privado;
- el grupo recibe únicamente una confirmación;
- si Telegram impide el mensaje privado, la licencia se revoca.

El usuario debe abrir primero el bot en privado y ejecutar `/start`.

## Comandos comunes

```text
/start
/menu
/Keygen
/id
/help
/license
/install
/upgrade
```

## Comandos administrativos

```text
/Keytime
/Setkeytime minutos
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

## Archivos persistentes

Estado modificable por el bot:

```text
/etc/ADM-db/token
/etc/ADM-db/Admin-ID
/etc/ADM-db/Reseller-ID
/etc/ADM-db/Allowed-Groups
/etc/ADM-db/Key-Duration-Minutes
```

Configuración root de despliegue:

```text
/etc/telebotgen/deploy.env
```

## Diagnóstico

```bash
systemctl status telebotgen.service telebotgen-update.path ghost-license-api.service --no-pager
journalctl -u telebotgen.service -u telebotgen-update.service -n 100 --no-pager
curl -sS http://127.0.0.1:8080/health | jq
sudo /usr/local/bin/telebotgen-deploy
stat -c '%U:%G:%a %n' /etc/telebotgen/deploy.env
```

## Desarrolladores

- `@Gh0stDeveloper`: integración, licencias e infraestructura.
- `@Jotchua_DevzZ`: proyecto original y desarrollo base.
