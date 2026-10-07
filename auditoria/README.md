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

## Avisos por Telegram
El nodo **Cada hora** corre de 8:05 a 22:05. Manda **un solo mensaje** con lo que venció en rojo y todavía no se había avisado, de los últimos 3 días:
```
⚠️ Comprobación pendiente
🔴 R-01842 · $500 · JUAN
Pedido P4509
comprar 10 block ligero
Falta: registro de compra en Microsip · 8 h
```
Cada pendiente se avisa una sola vez (`mov_aviso`). Antes de activarlo, pon `telegram_token` y `chat_id` en **Configuración (avisos)**.

## Instalar
1. `python3 auditoria/armar_flujo.py` genera `n8n/Auditoría de movimientos (Microsip).json`. Ya viene generado.
2. Importa el archivo en n8n, revisa la credencial de Postgres, pon el token y el chat del bot, y **activa** el flujo.
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
python3 auditoria/pruebas/probar_todo.py     # 71 casos del cruce y del semáforo (base de prueba 'auditoria')
node auditoria/pruebas/probar_nodos.js       # 29 casos: permisos por rol, fotos, avisos de Telegram, ligas
AHORA='2026-10-07 21:00' node auditoria/pruebas/servidor.js   # página en http://localhost:5683/webhook/auditoria-mov?k=...
```
