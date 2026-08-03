# TeleBotGen para Hex Tunnel

Bot de Telegram para distribuir códigos de activación temporales de Hex Tunnel, administrar accesos y atribuir cada instalación a un reseller público.

- Versión: `V3.2.0-rc.1`
- Rama estable predeterminada: `main`
- Sitio público: `https://hextunnel.duckdns.org`

## Modelo de activación

Una key es un código transferible de un solo uso:

1. el administrador configura cuántos minutos puede permanecer sin utilizarse;
2. un administrador, revendedor, cliente autorizado o miembro de un grupo permitido genera la key;
3. la key puede entregarse a otra persona;
4. al utilizarse correctamente queda vinculada a la IP pública de esa instalación;
5. el vencimiento original deja de afectar a la instalación activada;
6. la instalación continúa operativa y puede actualizarse mientras no sea revocada administrativamente.

La key no se conserva en texto plano en el servidor de autorizaciones. TeleBotGen mantiene una copia local protegida únicamente para entregar el aviso de activación: la elimina después de confirmar el aviso o automáticamente cuando vence sin utilizarse.

## Resellers

Cada administrador, revendedor o cliente autorizado puede configurar un nombre público:

```text
/setreseller Nombre público
/reseller
```

Si no se configura un nombre, se utiliza `Hex Tunnel Bot Gen`.

El reseller se incorpora a la autorización firmada y se muestra en el menú instalado de Hex Tunnel. No se acepta como un valor local manipulable por el instalador.

## Grupos permitidos

Administradores y revendedores pueden autorizar grupos:

```text
/allowgroup
/delgroup
/groups
```

El grupo queda asociado a quien lo autorizó. Sus miembros pueden ejecutar `/Keygen`, pero las keys creadas dentro del grupo utilizan el reseller del administrador o revendedor asociado al grupo.

En un grupo permitido:

- la key se publica en el mismo grupo;
- se publica también un enlace temporal del instalador;
- el enlace caduca, pero no sustituye la validación de la key;
- cuando la key se utiliza, el aviso llega al mismo grupo;
- el aviso incluye fecha, hora, key utilizada, IP pública y reseller.

## Roles

### Visitante

Puede usar únicamente las funciones públicas, como `/start`, `/help` e `/id`. No puede generar keys en privado.

### Cliente autorizado

Puede generar keys transferibles, configurar su reseller, consultar sus keys y solicitar enlaces temporales.

### Revendedor

Incluye las funciones de cliente y además puede añadir o retirar clientes y administrar sus grupos permitidos.

### Administrador

Incluye todas las funciones anteriores y puede administrar revendedores, duración global, revocaciones y reinicios de activación.

## Comandos principales

```text
/start
/help
/id
/Keygen
/mykeys
/license
/reseller
/setreseller Nombre
/install
/upgrade
```

Administradores y revendedores:

```text
/addclient telegram_id
/delclient telegram_id
/clients
/allowgroup [chat_id]
/delgroup [chat_id]
/groups
```

Solo administradores:

```text
/Keytime
/Setkeytime minutos
/licenses [telegram_id]
/revoke license_id motivo
/reset license_id motivo
/addreseller telegram_id
/delreseller telegram_id
/resellers
/service
/update
```

## Enlaces temporales

`/install` y `/Keygen` generan un enlace temporal que redirige al instalador público. El comando entregado usa HTTPS y el instalador continúa solicitando una key válida.

## Notificaciones de activación

TeleBotGen consulta eventos pendientes y envía el aviso al destino registrado:

- chat privado del generador para keys creadas por privado;
- grupo permitido para keys creadas en ese grupo.

Un evento solo se confirma después de que Telegram acepte el mensaje. Tras confirmarlo, la key completa se elimina del almacenamiento local del bot. Las copias de keys que vencen sin activarse también se purgan automáticamente.

## Archivos persistentes

```text
/etc/ADM-db/token
/etc/ADM-db/Admin-ID
/etc/ADM-db/Reseller-ID
/etc/ADM-db/Client-ID
/etc/ADM-db/Allowed-Groups
/etc/ADM-db/Group-Owners.tsv
/etc/ADM-db/Reseller-Names.tsv
/etc/ADM-db/Issued-Keys.tsv
/etc/ADM-db/Key-Duration-Minutes
```

Todos los archivos de estado utilizan permisos `600`; el directorio utiliza `700`.

## Instalación o actualización

```bash
curl -fsSL "https://raw.githubusercontent.com/Gh0stDeveloper/TeleBotGen/main/confbot.sh" \
  -o /tmp/confbot.sh
sudo bash /tmp/confbot.sh install
rm -f /tmp/confbot.sh
```

También puede actualizarse mediante:

```bash
sudo telebotgen-update
```

El despliegue utiliza respaldo, staging, validación, reemplazo transaccional y rollback automático.

## Separación de privilegios

`telebotgen.service` se ejecuta con un usuario sin privilegios:

```text
User=telebotgen
SupplementaryGroups=ghostlicense
NoNewPrivileges=true
ProtectSystem=strict
CapabilityBoundingSet=
```

La procedencia de las actualizaciones se conserva en `/etc/telebotgen/deploy.env`, propiedad de root y modo `600`. El bot solo puede solicitar una actualización creando `/etc/ADM-db/update.request`.

## Validación automatizada

GitHub Actions comprueba:

- sintaxis Bash y ShellCheck;
- compatibilidad con ShellBot;
- separación de roles;
- clientes explícitamente autorizados;
- propiedad de grupos y reseller heredado;
- keys transferibles sin bloqueo por propietario;
- enlaces temporales;
- notificaciones de activación y eliminación posterior de keys;
- purga automática de keys vencidas sin utilizar;
- ausencia de información interna en mensajes públicos;
- despliegue transaccional y separación de privilegios;
- uso de `main` como referencia predeterminada.

## Seguridad

Consulta [Rotación del token de Telegram](docs/SECURITY-NOTE-TOKEN-ROTATION.md).
