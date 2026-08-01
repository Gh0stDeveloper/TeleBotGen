# Rotación del token de Telegram

El token de `@BotFather` debe revocarse y regenerarse inmediatamente si aparece en:

- `journalctl`;
- `systemctl status`;
- `ps`, `top` o un listado de procesos;
- una captura de pantalla, chat o registro compartido.

TeleBotGen `V3.0.0-rc.4` desactiva el modo monitor de ShellBot y entrega las URL privadas a `curl` mediante un archivo de configuración temporal con permisos `600`, evitando que el token forme parte de la línea de comandos del proceso.

Después de rotarlo:

```bash
read -rsp "Nuevo token: " TOKEN; echo
printf '%s\n' "$TOKEN" > /etc/ADM-db/token
chmod 600 /etc/ADM-db/token
unset TOKEN
systemctl restart telebotgen.service
```

No se debe imprimir el contenido de `/etc/ADM-db/token` ni compartir salidas que contengan la URL completa de la API de Telegram.
