# Panel general (ligas con PIN)

Una sola página con **todas tus ligas**, protegida con PIN:

- **Planeador de compras**, **Producción de tinacos** y **Tablero del vendedor**: una liga por cada llave activa de `tablero_acceso` (admin, compras, producción, auditor, encargado).
- **Asistente de rutas**: la liga de oficina (`choferes_web`, nombre `*`).
- **Choferes**: la de oficina y la de cada chofer.
- **Monedero**: la app (pide su propio PIN).
- **Ligas propias**: Kommo, hojas de Google, etc. Las agregas, editas y quitas desde el panel, y puedes agruparlas.

Cada liga tiene **Copiar** y **Abrir**. El buscador filtra por página o por persona.
Si a una página le falta la llave, el panel te dice en qué flujo se crea.

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
`panel_pin` (una fila), `panel_sesion`, `panel_liga`. Se crean solas.
Las tablas de llaves (`tablero_acceso`, `choferes_web`) son las mismas que usan los demás flujos.

## Pruebas
`node panel/pruebas/probar_todo.js` corre 42 casos contra el Postgres de prueba: PIN, bloqueo, sesiones, ligas e inyección.
`node panel/pruebas/servidor.js` levanta la página en http://localhost:5682/webhook/mis-ligas.
