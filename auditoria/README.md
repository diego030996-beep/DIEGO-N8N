# Auditoría de movimientos (Microsip)

Control de comprobación encima de Microsip: **dinero que sale → comprobante → compra en Microsip → pedido → auditoría**.
El empleado reporta y sube la foto, el sistema cruza todo y la auditora solo revisa las excepciones.

## Quién hace qué
| Liga | Puede |
|---|---|
| **Empleado** (una liga por persona, `mov_empleado`) | Reportar movimientos con fotos, completar los suyos (más comprobantes, pedido), ver y buscar solo lo suyo |
| **Auditora** (`tablero_acceso` rol `auditora`) | Todo lo anterior + tablero, expediente de cualquier movimiento, aprobar, marcar inconsistencia, reabrir, vincular la compra de Microsip a mano, marcar "no requiere comprobación" |
| **Administrador** (rol `admin`) | Todo + alta y baja de empleados, ajustes, borrar un movimiento mal capturado (queda en bitácora) |

Todas las ligas aparecen en **Mis ligas**, con Copiar, Abrir y Regenerar.

## De dónde sale cada dato
- **Retiros de caja**: Punto de venta, documentos tipo `R` de `ms_ventas`, sin cancelados. El importe sale de `DOCTOS_PV_COBROS`.
  Al reportar un retiro, el folio, la fecha, la hora y el importe salen de Microsip: el empleado no los captura.
- **Compras**: `DOCTOS_CM` tipo `C` (compra) y `R` (recepción). Una recepción que ya pasó a compra cuenta una sola vez.
  El total es importe neto más impuestos.
- **Pedido**: Ventas `P`, `R` o `F`. Se compara solo el número (`P4509` = `P0004509`). Avisa si no existe o si está cancelado.
- **Retiros sin reportar** y **compras de contado sin comprobante** salen solos, aunque nadie los capture.

## Semáforo (la primera regla que aplica)
| | Cuándo |
|---|---|
| 🟢 Cuadrado | Retirado = comprobado (± tolerancia), la compra en Microsip coincide (si es tipo compra) y el pedido existe |
| 🟢 Aprobado | La auditora lo aprobó a mano (con nota opcional) |
| 🔴 FALTA COMPROBANTE | Sin foto después de la hora límite |
| 🔴 COMPRA NO REGISTRADA | Tipo compra, sin compra en Microsip después de la hora límite |
| 🔴 RETIRO SIN COMPROBAR | Retiro de caja que nadie reportó a la hora límite |
| 🔴 FALTA COMPROBANTE de la compra | Compra de contado en Microsip sin ningún movimiento ligado (al día siguiente a la hora límite) |
| 🔴 INCONSISTENCIA | La auditora lo marcó, con la nota de qué está mal |
| 🟠 Faltan comprobar $X / comprobado de más | Lo comprobado no llega a lo retirado, o se pasa |
| 🟠 La compra en Microsip es de $X | La compra encontrada no coincide con lo comprobado |
| 🟠 REVISAR PEDIDO | El pedido no existe o está cancelado |
| 🟠 Revisar compra | Hay varias compras posibles con el mismo importe |
| ⏳ En plazo | Todavía no llega la hora límite |

- **Hora límite**: la hora de cierre del día del retiro (20:00 por omisión). Un retiro hecho después del cierre vence al día siguiente.
- **Compra automática**: se busca una compra con el mismo importe (± tolerancia o ± el margen %) desde 2 días antes hasta N días después.
  Primero se compara contra lo comprobado y luego contra lo retirado. Una compra no se usa para dos movimientos.
  Si no es la correcta, la auditora la cambia en el expediente.
- **La IA no lee las fotos ni decide.** El sistema solo cruza importes, folios y fechas. Lo dudoso queda en 🟠 para que lo revise la auditora.

## Expediente
Cada movimiento guarda, para abrirlo meses después (Historial → `R-01842`):
- quién retiró, para qué y la descripción en caja;
- las fotos originales de los comprobantes;
- la compra de Microsip, indicando si se vinculó automática o a mano;
- el pedido;
- quién lo auditó y cuándo;
- la bitácora completa.

Las fotos se guardan en la base (`mov_comprobante.foto`, JPEG reducido a 1600 px).
Solo las ven la auditora, el administrador y el empleado que las subió.

## En el grupo de choferes (Telegram)
Todo se puede manejar desde el **grupo de choferes**, con un **bot de auditoría** que se agrega al grupo. El encargado y el dueño, que también están en el grupo, ven todo.

**Reportar desde el grupo:**
- Mandar la **foto del ticket** con el texto `R-01842 500 P4509 block ligero`. El folio del retiro, el importe, el pedido y el motivo pueden ir en cualquier orden.
- Sin retiro de caja: `350 gasolina tarjeta`.
- O **responder con la foto** a un aviso del bot. La foto queda ligada a ese retiro, movimiento o compra.
- El bot contesta en el grupo con el semáforo: 🟢 cuadrado, 🟠 qué falta o ⏳ hasta qué hora tiene.
- El chofer se identifica con el nombre que ya tiene en el bot de choferes (`choferes_tg`). Si no está ahí, se usa su nombre de Telegram.
- Fotos sin folio, sin importe y sin palabras como "ticket" o "comprobante" se ignoran, para no mezclarse con las fotos de entregas.

**Comandos:** `/pendientes` (resumen de hoy y problemas), `/folio R-01842` (cómo va), `/ayuda`.

**Avisos (cada hora de 8:05 a 22:05):**
- Un mensaje por cada movimiento que pasó la hora límite y sigue en 🔴 o 🟠.
- Etiqueta al responsable si mandó por Telegram.
- Trae "↩️ Responde a este mensaje con la foto".
- Se avisa una vez por estado: si pasa de 🟠 a 🔴, se vuelve a avisar.
- Lo que la auditora ya revisó no se repite.
- Si hay más de 8 a la vez, el resto va en un solo mensaje.

**Resumen del día (20:20):** 🟢/🟠/🔴, dinero sin comprobar, problemas de días anteriores y problemas por persona.
Si cambias la hora de cierre, mueve también la hora de "Resumen del día".

**Seguridad:**
- El bot solo atiende al grupo configurado.
- Telegram firma cada mensaje con la `secreto` (`X-Telegram-Bot-Api-Secret-Token`).
- En los mensajes del grupo nunca se ponen ligas con llave.

**Por qué un bot aparte:** Telegram solo deja un receptor de mensajes por bot. El bot de choferes ya lo usa el flujo "ML inventario + ventas (Telegram)". Con un bot propio no se toca ese flujo.
**No pongas el token del bot de choferes aquí**: "Conectar bot" le quitaría sus mensajes a ese flujo.

## Instalar
1. `python3 auditoria/armar_flujo.py` genera `n8n/Auditoría de movimientos (Microsip).json`. Ya viene generado.
2. Importa el archivo en n8n y revisa la credencial de Postgres.
   Crea el bot de auditoría (ver la nota dentro del flujo) y pon su token en **Configuración del bot**.
   **Activa** el flujo y corre **Conectar bot** una vez.
3. Corre **Ver ligas**: crea la llave de la auditora si no existe y te da las ligas.
4. Con la liga de administrador entra a **Empleados** y da de alta a quien maneja dinero. Cada uno recibe su liga.
5. En **Ajustes** revisa:
   - la hora límite y la tolerancia;
   - qué retiros no se auditan, por ejemplo `DEPOSITO|CORTE`;
   - qué compras piden comprobante: de contado, de mostrador, todas o ninguna.

La auditoría empieza **el día que se instala**: no revisa todo el pasado de Microsip. Se cambia en Ajustes → "Auditar desde".

## Archivos
- `sql/esquema.sql`: tablas `mov_*`.
- `sql/_ctx.sql`: configuración.
- `sql/_mov.sql`: el cruce completo (retiros, compras, pedidos, semáforo).
- `sql/<op>.sql`: una consulta por operación.
- `n8n/preparar.js`: permisos y validación.
- `n8n/armar.js`: respuesta.
- `pagina.html`: la página.

## Pruebas
```
python3 auditoria/pruebas/probar_todo.py     # 84 casos del cruce, del semáforo y del registro por Telegram (base de prueba 'auditoria')
node auditoria/pruebas/probar_nodos.js       # 49 casos: permisos, fotos, mensajes del grupo, avisos, resumen, ligas
AHORA='2026-10-07 21:00' node auditoria/pruebas/servidor.js   # página en http://localhost:5683/webhook/auditoria-mov?k=...
```
