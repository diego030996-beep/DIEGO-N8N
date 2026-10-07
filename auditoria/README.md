# Auditoría de movimientos (Microsip)

Control de comprobación encima de Microsip, para el **corte de caja**:
- **Cobros**: toda forma de pago **menos efectivo** debe tener comprobante.
  - Tarjeta: voucher.
  - Transferencia y Mercado Pago: comprobante.
  - Venta a crédito: foto del **ticket firmado**.
  - Efectivo: lo firma el dueño en el corte.
- **Retiros de caja** (siempre en efectivo): dinero que sale → comprobante → compra en Microsip → pedido.
  Los retiros de **préstamo** y **nómina** no piden comprobante.
El empleado reporta y sube la foto, el sistema cruza todo y la auditora solo revisa las excepciones.

## Quién hace qué
| Liga | Puede |
|---|---|
| **Empleado** (una liga por persona, `mov_empleado`) | Reportar movimientos con fotos, completar los suyos (más comprobantes, pedido), ver y buscar solo lo suyo |
| **Auditora** (`tablero_acceso` rol `auditora`) | Todo lo anterior + tablero, expediente de cualquier movimiento, aprobar, marcar inconsistencia, reabrir, vincular la compra de Microsip a mano, marcar "no requiere comprobación" |
| **Administrador** (rol `admin`) | Todo + alta y baja de empleados, ajustes, borrar un movimiento mal capturado (queda en bitácora) |

Todas las ligas aparecen en **Mis ligas**, con Copiar, Abrir y Regenerar.

## Corte de caja (pestaña "Corte de caja")
Reporte del día listo para imprimir:
- **Totales**: cobrado en caja, cobrado en efectivo, retiros (y cuántos no piden comprobante) y efectivo neto (efectivo − retiros; sin fondo de caja).
- **Cobros por forma de pago**: tickets, importe y cuántos tienen comprobante o faltan, con el monto que falta.
- **Retiros**: estado de cada uno. Préstamo y nómina salen como "no pide". Se ve la recepción ligada a cada compra.
- **Firma**, en lugar de la libreta. La auditora o el administrador escriben el efectivo entregado y queda guardado:
  - lo esperado, lo entregado y la diferencia;
  - lo que seguía pendiente al firmar;
  - quién firmó y cuándo (`mov_corte` y bitácora).

  Se puede volver a firmar. El encargado ve el corte, pero no lo firma.

## Recepción de compra y pedidos
- Una compra de mercancía debe tener su **recepción de compra** en Microsip y el importe tiene que cuadrar.
  En el expediente se ve **qué llegó** (artículos y unidades de `DOCTOS_CM_DET`).
- **Cuadre por pedido** (pestaña "Pedidos" y en el expediente): lo pedido (`ms_ventas_det` del pedido) contra lo que ha llegado en todas las recepciones ligadas a ese pedido.
  Sirve cuando se compra por partes, por ejemplo 100 + 200 + 300 de un millar de block.
- 🟠 **"La recepción trae X y no está en el pedido"**: se compró algo que el pedido no lleva.

## Retiros del mes (pestaña "Retiros del mes")
Muestra todos los retiros de un mes, aunque sean de antes de empezar la auditoría:
- agrupados en "no piden comprobante", "gasto" y "compra / otro";
- con las palabras que más se repiten y su importe.

Sirve para ajustar en Ajustes qué retiros no piden comprobante y cuáles son gasto.
Al escoger un retiro para comprobarlo, si su descripción es de gasto, el tipo se pone solo en "Gasto".

## De dónde sale cada dato
- **Retiros de caja**: Punto de venta, documentos tipo `R` de `ms_ventas`, sin cancelados. El importe sale de `DOCTOS_PV_COBROS`.
  Al reportar un retiro, el folio, la fecha, la hora y el importe salen de Microsip: el empleado no los captura.
- **Compras**: `DOCTOS_CM` tipo `C` (compra) y `R` (recepción). Una recepción que ya pasó a compra cuenta una sola vez.
  El total es importe neto más impuestos.
- **Pedido**: Ventas `P`, `R` o `F`. Se compara solo el número (`P4509` = `P0004509`). Avisa si no existe o si está cancelado.
- **Cobros**: `DOCTOS_PV_COBROS` de tickets de caja (`V`/`P`, sin cancelados), por ticket y forma.
  Piden comprobante todas las formas de `FORMAS_COBRO`, menos las de "Formas de cobro que NO piden comprobante" (por omisión `EFECTIVO|CAMBIO`).
  Tarjeta pide **voucher**; crédito, **ticket firmado**; transferencia y Mercado Pago, **comprobante**.
  El importe es el de esa forma de pago en ese ticket. Si Microsip trae `REFERENCIA` o `NUM_AUTORIZACION`, también se muestra.
- **Retiros que no piden comprobante**: los que dicen préstamo o nómina en la descripción (Ajustes → `PR[EÉ]STAMO|N[OÓ]MINA`). Se pueden agregar más palabras.
- **Retiros sin reportar** salen solos, aunque nadie los capture. Las **compras de contado sin comprobante** también, si se activa en Ajustes.

## Semáforo (la primera regla que aplica)
| | Cuándo |
|---|---|
| 🟢 Cuadrado | Retirado = comprobado (± tolerancia), la compra en Microsip coincide (si es tipo compra) y el pedido existe |
| 🟢 Aprobado | La auditora lo aprobó a mano (con nota opcional) |
| 🔴 FALTA COMPROBANTE | Sin foto después de la hora límite |
| 🔴 FALTA RECEPCIÓN de compra | Tipo compra, sin recepción en Microsip después de la hora límite |
| 🔴 RETIRO SIN COMPROBAR | Retiro de caja que nadie reportó a la hora límite |
| 🔴 FALTA VOUCHER / TICKET FIRMADO / COMPROBANTE DE TRANSFERENCIA / DE MERCADO PAGO | Cobro con esa forma de pago sin foto a la hora límite |
| 🟠 La recepción trae X y no está en el pedido | Lo que llegó no es de lo que se pidió |
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

## Avisos por Telegram (solo avisos)
Todo se captura y se revisa en la **web**, que también se abre desde el celular. Telegram **solo manda avisos**.

- Se usa el bot de **Monedero** únicamente para mandar mensajes. No se conecta, así que el flujo del monedero sigue igual.
- **chat_ids** (en "Configuración del bot") dice a quién le llegan, separados por coma: el tuyo y el del encargado de caja.
  Para agregar al encargado:
  1. Que abra @Monedero_DISACAMBOT y le dé *Iniciar*.
  2. Que vea su número de chat con @userinfobot.
  3. Agrega ese número a la lista.
- **Cada hora** (8:05 a 22:05) manda **un mensaje** con lo que pasó la hora límite y sigue en 🔴 o 🟠:
  ```
  ⚠️ Comprobación pendiente
  🔴 R-01842 · $500 · JUAN
  Pedido P4509
  comprar 10 block ligero
  Falta: ticket + registro de compra en Microsip · 8 h
  ```
  - Se avisa una vez por estado: si empeora de 🟠 a 🔴, se vuelve a avisar.
  - Lo que la auditora ya revisó no se repite.
- **Resumen del día** (20:20): 🟢/🟠/🔴, dinero sin comprobar y los problemas.
  Si cambias la hora de cierre en Ajustes, cambia también la hora de este nodo.

## Instalar
1. `python3 auditoria/armar_flujo.py` genera `n8n/Auditoría de movimientos (Microsip).json`. Ya viene generado.
2. Importa el archivo en n8n y revisa la credencial de Postgres.
   En **Configuración del bot** pon el token del bot y los chats; la copia que te mandé ya los trae.
   **Activa** el flujo.
3. Corre **Ver ligas**: crea la llave de la auditora si no existe y te da las ligas.
4. Con la liga de administrador entra a **Empleados** y da de alta a quien maneja dinero. Cada uno recibe su liga.
5. En **Ajustes** revisa:
   - la hora límite y la tolerancia;
   - qué retiros no se auditan, por ejemplo `DEPOSITO|CORTE`;
   - qué compras de Microsip piden comprobante. Por omisión, ninguna: solo se auditan los retiros de caja.

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
python3 auditoria/pruebas/probar_todo.py     # 112 casos: cruce, cobros, semáforo, corte y firma, pedidos, retiros del mes (base de prueba 'auditoria')
node auditoria/pruebas/probar_nodos.js       # 36 casos: permisos, fotos, avisos, resumen y ligas
AHORA='2026-10-07 21:00' node auditoria/pruebas/servidor.js   # página en http://localhost:5683/webhook/auditoria-mov?k=...
```
