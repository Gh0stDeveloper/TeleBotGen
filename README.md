# TeleBotGen para Hex Tunnel

TeleBotGen administra por Telegram las licencias comerciales de Hex Tunnel mediante `GhostDeveloperLicenseServer`.

Versión: `3.0.0-rc.2`

## Arquitectura

```text
Usuario de Telegram
  └── /Keygen
       └── TeleBotGen obtiene message_from_id
            └── http://127.0.0.1:8080/api/v1/admin/licenses
                 └── GhostDeveloperLicenseServer
                      ├── licencia vinculada al Telegram ID
                      ├── autorización HTTPS firmada
                      ├── activación vinculada a IP
                      ├── lease renovable
                      └── descarga privada de un solo uso
```

El bot y la API se ejecutan en la misma VPS. Los endpoints administrativos no se publican en Internet y el antiguo servidor `HexGen` del puerto `8888` queda desactivado.

## Requisitos

- `GhostDeveloperLicenseServer` instalado y activo en `127.0.0.1:8080`.
- Token administrativo en `/etc/ghostdeveloper-license/secrets/admin-token`.
- Debian 12, Ubuntu 22.04 o Ubuntu 24.04 para la VPS del bot.
- Token de Telegram creado mediante `@BotFather`.

Hex Tunnel debe instalarse en una VPS distinta, dedicada y con arquitectura amd64/x86_64.

## Instalación de la rama RC

```bash
curl -fsSL "https://raw.githubusercontent.com/Gh0stDeveloper/TeleBotGen/feat/hextunnel-license-integration/confbot.sh" \
  -o /tmp/telebotgen-conf.sh && \
TELEBOTGEN_REF=feat/hextunnel-license-integration sudo -E bash /tmp/telebotgen-conf.sh
```

El configurador permite guardar el token, definir el administrador inicial, autorizar grupos, configurar la duración global de las keys, instalar archivos, controlar el servicio y verificar la API.

## Generación automática de keys

El usuario ejecuta únicamente:

```text
/Keygen
```

No debe proporcionar:

- Telegram ID;
- nombre de usuario;
- minutos;
- duración;
- ID de otro cliente.

TeleBotGen usa `message_from_id` o `callback_query_from_id`, según el tipo de interacción. En un chat privado ese valor corresponde al usuario. Dentro de un grupo, se utiliza el ID del miembro que envió el comando y nunca el ID negativo del grupo.

La licencia queda asociada a ese mismo usuario mediante `owner_telegram_id`.

## Duración global

La duración de las nuevas keys la define exclusivamente el administrador. Se guarda en:

```text
/etc/ADM-db/Key-Duration-Minutes
```

Valor predeterminado:

```text
240 minutos
```

Desde Telegram:

```text
/Keytime
/Setkeytime 1440
```

También puede configurarse desde el menú de instalación de la VPS.

Los usuarios no pueden modificar la duración desde `/Keygen`.

## Una licencia activa por usuario

Antes de generar una key, el bot consulta las licencias del remitente. Cuando ya existe una licencia activa, no crea otra y muestra el tiempo restante.

La API no conserva la key completa en texto plano, por lo que una key perdida debe revocarse administrativamente antes de emitir una nueva.

## Chats privados

Cualquier usuario que pueda comunicarse con el bot puede ejecutar `/Keygen`. La key se genera para su propio Telegram ID y se entrega en el mismo chat privado.

## Grupos permitidos

Los grupos autorizados se guardan en:

```text
/etc/ADM-db/Allowed-Groups
```

Un administrador puede autorizar el grupo ejecutando dentro de él:

```text
/allowgroup
```

En un grupo permitido:

- todos los miembros pueden ejecutar `/Keygen`;
- no necesitan rol de cliente, administrador o revendedor;
- cada miembro genera únicamente su propia key;
- la duración es la configurada por el administrador;
- la key y el instalador se envían por mensaje privado;
- el grupo recibe solamente una confirmación;
- si Telegram bloquea la entrega privada, la licencia se revoca automáticamente.

El usuario debe abrir primero el bot en privado y ejecutar `/start` para que Telegram permita el mensaje directo.

## Menús

### Grupo autorizado

El menú del grupo no muestra roles. Presenta:

- Generar mi key;
- Mi licencia;
- Mi ID;
- Ayuda.

### Cliente con licencia activa

`/start` muestra:

- tiempo restante;
- estado;
- vencimiento;
- IP vinculada;
- instalador;
- actualización.

### Administrador

Puede administrar duración, licencias, revendedores, grupos, API y diagnósticos.

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

## Instalador entregado al usuario

El bot entrega un comando que:

1. instala `curl` y certificados cuando faltan;
2. descarga `https://ghostdeveloper.duckdns.org/install.sh`;
3. solicita la key;
4. verifica la autorización RSA;
5. valida SHA-256;
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
/etc/ADM-db/Key-Duration-Minutes
/etc/ADM-db/repository.env
```

Los archivos privados usan permisos `600`; el directorio de estado utiliza `700`.

## Diagnóstico

```bash
systemctl status telebotgen.service ghost-license-api.service --no-pager
journalctl -u telebotgen.service -n 100 --no-pager
curl -sS http://127.0.0.1:8080/health | jq
cat /etc/ADM-db/Key-Duration-Minutes
ss -lntp | grep -E ':(8080|8888)\b'
```

La API debe escuchar solamente en `127.0.0.1:8080` y no debe existir ningún listener en `8888`.

## Desarrolladores

- `@Gh0stDeveloper`: integración, licencias e infraestructura.
- `@Jotchua_DevzZ`: proyecto original y desarrollo base.
