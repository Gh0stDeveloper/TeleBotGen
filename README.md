# TeleBotGen para Hex Tunnel

TeleBotGen administra por Telegram la generación de keys de activación de un solo uso para Hex Tunnel.

Esta versión reemplaza el generador heredado por un flujo controlado mediante systemd, tokens criptográficos, expiración automática y consumo atómico.

## Estado

Versión: `2.0.0-rc.1`

Sistemas admitidos para el VPS del bot:

- Debian 12.
- Ubuntu 22.04 LTS.
- Ubuntu 24.04 LTS.
- Arquitectura amd64/x86_64.

Hex Tunnel se instala desde el release candidate fijado por el bot. El instalador pide la key antes de mostrar el selector de módulos.

## Componentes

- `confbot.sh`: instalación, actualización y configuración local.
- `sources/BotGen.sh`: proceso del bot de Telegram.
- `sources/gerar_key`: generación de keys y comando de instalación.
- `http-server.sh`: validación y consumo de keys en el puerto TCP 8888.
- `update.sh`: actualización atómica desde el repositorio configurado.
- `telebotgen.service`: servicio del bot.
- `hexgen-http.service`: servidor de validación de keys.

## Instalación de esta rama RC

Ejecutar como root en un VPS limpio:

```bash
curl -fsSL "https://raw.githubusercontent.com/Gh0stDeveloper/TeleBotGen/feat/hextunnel-license-integration/confbot.sh" -o /tmp/telebotgen-conf.sh && sudo bash /tmp/telebotgen-conf.sh
```

Después de fusionar esta rama en `main`, el comando estable será:

```bash
curl -fsSL "https://raw.githubusercontent.com/Gh0stDeveloper/TeleBotGen/main/confbot.sh" -o /tmp/telebotgen-conf.sh && sudo bash /tmp/telebotgen-conf.sh
```

El configurador permite:

1. Guardar el token entregado por `@BotFather`.
2. Guardar el ID de Telegram del administrador.
3. Configurar la IP pública o dominio del servidor de keys.
4. Instalar o actualizar todos los archivos.
5. Iniciar o detener el bot.
6. Iniciar o detener el servidor de validación.
7. Enviar un mensaje de prueba.
8. Consultar servicios, logs y puerto de escucha.

## Red y firewall

El servidor de validación escucha por defecto en:

```text
TCP 8888
```

El puerto debe estar permitido en el firewall del VPS y accesible desde los servidores donde se instalará Hex Tunnel.

El host público puede ser:

- la IP pública del VPS del bot;
- un dominio o subdominio con registro A apuntando a esa IP.

## Flujo de activación

1. El administrador autoriza el ID de Telegram mediante `/add`.
2. El usuario ejecuta `/keygen`.
3. El bot crea un token aleatorio de 40 caracteres hexadecimales.
4. La key se guarda con permisos restringidos y caduca en 240 minutos.
5. El bot entrega:
   - la key `HexGen/...`;
   - el comando de instalación fijado a un commit validado de Hex Tunnel.
6. Hex Tunnel solicita la key antes del menú modular.
7. El servidor verifica formato, vigencia y, cuando corresponda, IP fija.
8. La key se mueve atómicamente a estado de consumo y deja de ser válida.
9. Un segundo intento devuelve `KEY INVALIDA!`.
10. El propietario recibe una notificación de activación.

## Comandos del bot

Para usuarios autorizados:

```text
/keygen    Generar una key de un solo uso.
/install   Mostrar el instalador Hex Tunnel RC.
/menu      Abrir el panel.
/ID        Mostrar el ID de Telegram.
/ayuda     Mostrar instrucciones.
```

Para administradores:

```text
/add       Autorizar un ID.
/del       Revocar un ID.
/list      Mostrar IDs autorizados.
/power     Controlar el servidor de validación.
/infosys   Mostrar información del VPS.
/cache     Liberar caché del sistema.
/update    Actualizar TeleBotGen.
/reboot    Reiniciar el VPS.
```

## Archivos persistentes

```text
/etc/ADM-db/token
/etc/ADM-db/Admin-ID
/etc/ADM-db/User-ID
/etc/ADM-db/public-host
/etc/ADM-db/repository.env
/etc/http-shell/
/var/log/telebotgen-license.log
```

Los tokens, IDs, metadata y logs sensibles se guardan con permisos `600`; los directorios privados usan `700`.

## Diagnóstico

```bash
systemctl status telebotgen.service hexgen-http.service --no-pager
journalctl -u telebotgen.service -u hexgen-http.service --since today --no-pager
ss -lntp | grep ':8888'
tail -n 100 /var/log/telebotgen-license.log
```

## Validación automática

GitHub Actions comprueba:

- sintaxis Bash de todos los scripts;
- errores de ShellCheck;
- ausencia de comandos de instalación obsoletos;
- generación de una key;
- primera activación válida;
- consumo de la key;
- rechazo del segundo uso;
- rechazo de métodos HTTP no admitidos.

## Límite de seguridad actual

El canal `TeleBotGen` conserva temporalmente el protocolo HTTP heredado para que las keys actuales sean compatibles con Hex Tunnel. El instalador normal de producción continúa separado y utiliza autorización HTTPS firmada, SHA-256 y paquetes privados.

Para una edición comercial se debe reemplazar este puente por la API de licencias firmada y el servidor privado de distribución descritos en el proyecto Hex Tunnel.
