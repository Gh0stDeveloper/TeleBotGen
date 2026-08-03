# Rotación del token de Telegram

El token de `@BotFather` debe revocarse y regenerarse inmediatamente si aparece en:

- `journalctl`;
- `systemctl status`;
- `ps`, `top` o un listado de procesos;
- una captura de pantalla, chat o registro compartido;
- un commit, issue, pull request o artefacto de CI.

TeleBotGen `V3.1.0-rc.1` entrega las URL privadas de Telegram a `curl` mediante archivos de configuración temporales con permisos `600`, evitando que el token forme parte de la línea de comandos del proceso. El servicio se ejecuta como el usuario sin privilegios `telebotgen` y solo puede escribir en `/etc/ADM-db`.

## Rotar el token

1. Revoca el token comprometido mediante `@BotFather`.
2. Genera un token nuevo.
3. Guárdalo sin imprimirlo en la terminal:

```bash
read -rsp "Nuevo token: " TOKEN; echo
sudo install -o telebotgen -g telebotgen -m 600 /dev/null /etc/ADM-db/token
printf '%s\n' "$TOKEN" | sudo tee /etc/ADM-db/token >/dev/null
unset TOKEN
sudo systemctl restart telebotgen.service
```

4. Comprueba el servicio sin mostrar el token:

```bash
systemctl is-active telebotgen.service
journalctl -u telebotgen.service -n 30 --no-pager
```

## Verificación de exposición

No ejecutes comandos que impriman `/etc/ADM-db/token`. Para comprobar únicamente propietario y permisos:

```bash
stat -c '%U:%G:%a %n' /etc/ADM-db/token
```

El resultado esperado es:

```text
telebotgen:telebotgen:600 /etc/ADM-db/token
```

También debe comprobarse que el token no aparezca en procesos activos:

```bash
ps -eo pid,user,args | grep -E '[a]pi\.telegram\.org/bot|[t]elebotgen'
```

La salida de diagnóstico, los archivos temporales y los artefactos de CI nunca deben contener la URL completa de la API de Telegram ni el contenido de `/etc/ADM-db/token`.
