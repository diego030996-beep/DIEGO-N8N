# Panel general (ligas con PIN)

Una sola página con **todas tus ligas**, protegida con PIN:

- **Planeador de compras**, **Producción de tinacos** y **Tablero del vendedor**: una liga por cada llave activa de `tablero_acceso` (admin, compras, producción, auditor, encargado).
- **Asistente de rutas**: la liga de oficina (`choferes_web`, nombre `*`).
- **Choferes**: la de oficina y la de cada chofer.
- **Auditoría de movimientos**: administrador, auditora y la liga de cada empleado (`mov_empleado`).
- **Monedero**: la app (pide su propio PIN).
- **Ligas propias**: Kommo, hojas de Google, etc. Las agregas, editas y quitas desde el panel, y puedes agruparlas.

Cada liga tiene **Copiar** y **Abrir**. El buscador filtra por página o por persona.
Si a una página le falta la llave, el panel te dice en qué flujo se crea.

## Regenerar ligas (si una se filtra)
- Cada liga con llave tiene un botón **↻ Regenerar**. Crea una llave nueva y la anterior deja de abrir **en ese momento**.
  Quien use la liga vieja recibe "sin permiso" del flujo correspondiente.
- Algunas llaves abren varias páginas (la de administrador abre compras, producción y vendedor; la de auditor abre compras y producción;
  la de oficina abre rutas y choferes). Antes de regenerar, el panel te dice qué páginas cambian.
- **Regenerar todas** (emergencia) pide tu PIN otra vez. Cambia todas las llaves, incluso las desactivadas, y cierra tus sesiones del panel en otros dispositivos.
  Un PIN equivocado cuenta para el bloqueo de 5 intentos.
- Solo cambian las llaves `k` de `tablero_acceso`, `choferes_web` y `mov_empleado`, en el mismo renglón (mismo rol, mismo chofer).
  **No cambia** las direcciones de n8n, los flujos ni las credenciales de Microsip, Telegram, WhatsApp, OpenAI, etc.
- Las llaves nuevas tienen 64 caracteres hexadecimales: dos `gen_random_uuid()` de Postgres, que usan el generador criptográfico del sistema (244 bits aleatorios).
- Cada regeneración queda en `panel_rotacion` con la fecha. Ahí solo se guarda el hash de la llave, nunca la llave.
  El panel muestra "regenerada el …" en cada liga y la fecha de la última vez que regeneraste todas.
- El panel se actualiza solo con las ligas nuevas; solo tienes que mandarlas a quien las use.
- Si regeneras la llave de administrador, también cambia la liga para poner o reponer el PIN. Vuelve a correr el nodo si la necesitas.

## Instalar
1. `python3 panel/armar_flujo.py` genera `n8n/Panel general (ligas con PIN).json`. Ya viene generado.
2. Importa el archivo en n8n, revisa la credencial de Postgres y **activa** el flujo.
3. Corre a mano el nodo **"Mi liga para poner PIN"**. Te da dos ligas:
   - `poner_pin`: ábrela **una vez** para crear tu PIN. Lleva la llave de administrador, así que no la compartas.
   - `panel` (https://ai.adhesipro.com.mx/webhook/mis-ligas): esta es la que guardas en tu celular. Te pide el PIN cada vez.

## Seguridad
- El PIN es de 4 a 8 números y se guarda con sal y hash SHA-256, nunca en texto. No acepta PIN fáciles (1234, 0000…).
- Después de 5 intentos fallidos el panel se bloquea 15 minutos.
- La sesión dura 12 horas, o 30 días si marcas "Recordar este dispositivo". **Salir** la cierra.
- **Cambiar PIN** pide el PIN actual y cierra las sesiones de los demás dispositivos.
- **Si olvidas el PIN**, vuelve a correr "Mi liga para poner PIN" y abre `poner_pin`: lo reemplaza y cierra todas las sesiones.
- El flujo no guarda las ejecuciones exitosas, así que el PIN no queda en el historial de n8n.

## Tablas
`panel_pin` (una fila), `panel_sesion`, `panel_liga`, `panel_rotacion`. Se crean solas.
Las tablas de llaves (`tablero_acceso`, `choferes_web`) son las mismas que usan los demás flujos.

## Pruebas
`node panel/pruebas/probar_todo.js` corre 72 casos contra el Postgres de prueba: PIN, bloqueo, sesiones, ligas, regeneración (incluye revisar que la llave vieja quede denegada) e inyección.
`node panel/pruebas/servidor.js` levanta la página en http://localhost:5682/webhook/mis-ligas.
