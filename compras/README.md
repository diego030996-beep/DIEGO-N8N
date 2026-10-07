# Planeador de compras (Microsip → n8n)

Página web para comprar con máximos y mínimos y dejar la evidencia lista para el auditor. Funciona como las otras
páginas: un flujo de n8n que lee las tablas de Microsip que ya se copian a Postgres (`ms_*` y `ms_raw`).

| Pestaña | Qué hace | Lineamiento |
|---|---|---|
| A/B/C y máximos-mínimos | Cada mes (día 1, 3:40 a.m.) calcula el 80/20 con la venta de los últimos 6 meses, los C y los máximos/mínimos | 1.2.1.1 · 1.2.2.2 |
| Planeador | Tarjetas por proveedor con orden estimada ($ e IVA), estados Crítico / Por pedir / Próximo / Bien, presupuesto y «Generar órdenes». Según el calendario (A cada semana, B y C cada 15 días por proveedor) muestra existencia, por recibir, mínimo, máximo y sugerido. Capturas lo que compras y la razón si es distinto | 1.2.2.3 · 1.2.2.4 |
| Seguimiento de OC | Órdenes abiertas, parciales y atrasadas; planes guardados que aún no son OC; días de entrega reales por proveedor | 1.3.1.1 |
| Presentaciones | Tonelada, millar, viaje… = N unidades del artículo base (solo cuentan cuando las confirmas) | — |
| Registro de compras | Liga cada plan con su orden de compra de Microsip (sola o por folio), reconstruye meses pasados y exporta el registro mensual | 1.3.1.1 |
| Configuración | Todas las reglas, los proveedores, los ajustes por artículo y la lista de razones. **Todo se guarda en la base de datos** | — |

Cómo se clasifica (se explica también en la página y en el Excel):

- **A**: los artículos que juntos suman el primer **80%** de la venta (importe sin IVA) de los últimos **6 meses**
  completos. Cuentan tickets de punto de venta menos devoluciones y remisiones; no cuentan cancelados ni tickets de más de $500,000.
- **B**: el siguiente **15%** de la venta.
- **C**: el último **5%** (los que se venden de vez en cuando); también los que se vendieron en los últimos **12 meses** pero no
  en esos 6, y los que se venden por primera vez en el mes (C provisional hasta el siguiente cálculo).
- **No entran**: las líneas o grupos de Microsip que digan `tinaco|cisterna` (fabricación propia), los dados de baja y los
  marcados a mano. La página lo avisa y sus OCs no salen como pendientes en el registro.

Mínimo, punto de reorden y máximo (método recomendado; se cambia en la página):

- **Mínimo (stock de seguridad)** = Z × variación de la venta diaria × √(días de entrega + días entre revisiones).
  Z sale del nivel de servicio: A 95 % (1.65), B 90 % (1.28), C 85 % (1.04). La variación se mide semana por semana.
- **Punto de reorden** = venta diaria × (días de entrega + días entre revisiones) + mínimo. Cuando existencia + por recibir
  llega aquí, se pide. Revisión: A cada 7 días, B y C cada 15.
- **Máximo** = punto de reorden + venta diaria × días de inventario (A 7, B 15, C 30). El sugerido es máximo − existencia − por recibir,
  redondeado al empaque.
- **Rotación** = % de semanas con venta: mucho ≥ 50 %, medio ≥ 20 %, poco abajo. Los que rotan poco (se venden de vez en cuando)
  no llevan colchón: se tiene **1 pieza y se pide solo cuando se acaba** (mínimo 1, punto de reorden 0, máximo 1; el número
  de piezas se cambia en Configuración).
- Ningún mínimo queda en 0 y siempre máximo > punto de reorden y máximo ≥ mínimo. También está el **método simple**
  (mínimo = venta diaria × (entrega + días de seguridad)) por si el auditor pide ese.

En cada renglón del planeador se ve la **última venta** (al día de hoy) y la **última recepción** (fecha, piezas y proveedor
si fue otro). Planeador: vista **Por proveedor** o **Todos los productos** (todo lo que hay que pedir, agrupado por proveedor; "Guardar todo"
guarda un plan por proveedor).

**Archivo para importar la OC en Microsip**: en el planeador (después de guardar) y en cada plan del registro hay un botón
que descarga un `.txt` con el formato de Microsip, sin encabezado: `CLAVE,UNIDADES,PRECIO` (ej. `CEM1B,40,1`). Las unidades son las
que confirmaste y el precio es el **último costo** del artículo en Microsip; si no tiene, el precio de su última compra (y avisa si
alguno queda en 0).

**Compras de más**: si lo que compras pasa del sugerido o te deja arriba del máximo, el planeador lo marca en rojo y pide
confirmación al guardar; en el registro se marca cada renglón de OC con compra de más (y si la OC trae más que lo planeado).
Sale también en el Excel.

**OC anteriores al planeador** (reconstruidas de Microsip): la razón por omisión es «Autorizó gerencia»; hay un botón para
ponérsela a las que se quedaron sin razón. Se puede cambiar renglón por renglón.

**Casi no se vende**: en el planeador, a los productos que rotan poco, se vendieron una vez, llevan más de 90 días sin venta
o cuya existencia alcanza para más de 90 días, aparece el aviso con **Se queda** / **Se va (pausar)**. Lo pausado sale del
planeador y del cálculo hasta que lo regreses en **Limpieza de catálogo → Pausados**.

**Limpieza de catálogo**: lista lo que se vendió una sola vez en 12 meses y los posibles duplicados donde solo cambia la marca
(medidas, números, colores y materiales no cuentan como marca). "Ya no comprar" / "Se va" excluye el artículo; se puede deshacer.

## Lo nuevo (octubre 2026)

- **Presentaciones y conversiones**: si confirmas `TONELADA CEMENTO 50 KG = 20 × CEMENTO 50 KG`, sus ventas, existencias y OCs se suman al saco
  y se calcula una sola compra. La página sugiere las parejas por el nombre (misma medida, a lo más una palabra distinta) pero **ninguna cuenta hasta
  que la confirmas**; las equivalencias de Microsip (`COSTOS_ARTICULOS`) ya cuentan. Lo que no tiene base (varilla por tonelada, calidra, block por millar)
  sale en una lista para que escribas el artículo y el factor.
- **Servicios y VARIOS fuera**: flete, maniobra, mano de obra, renta… y los artículos genéricos «VARIOS» no entran al A/B/C ni al planeador
  (las palabras se cambian en Configuración).
- **Pedidos abiertos, parciales y atrasados**: se cuenta lo que falta de cada renglón de OC (pedido − recibido por las recepciones ligadas).
  Una OC que pasó sus días de entrega + gracia queda **atrasada**: no cuenta como por recibir, sale en el planeador y en Seguimiento hasta que digas
  «sigue en camino», «ya llegó» o «cancelada». Nunca desaparece sola.
- **Revisar datos**: existencia negativa (con el almacén), unidad que no cuadra con el nombre, sin proveedor, días de entrega desconocidos,
  OC atrasada, plan guardado sin OC. La cantidad sale como **provisional**. Nunca se ajusta el inventario.
- **Política por producto** (en «Ver cálculo»): mantener un mínimo, solo bajo pedido o pausar resurtido. El mínimo respeta el empaque.
- **Historial diario del inventario**: el nodo «Diario 23:50» guarda una foto de las existencias. Con 30 días o más, el cálculo descuenta los días
  que el producto estuvo agotado (si no, la venta diaria sale baja).
- **Prioridades, costos y presupuesto**: costo por renglón (último costo de Microsip o precio de la última compra), orden estimada por proveedor con IVA
  y total. Si escribes un presupuesto, se marca qué cabe por prioridad (críticos y A primero) y qué queda pendiente; nada se oculta.
- **Duplicados**: solo se proponen si lo único que cambia es una **marca** de la lista (Configuración → Marcas) y tienen la misma unidad.
- **Días de entrega reales**: mediana de días de la OC a su primera recepción (último año). Si escribes los días del proveedor, mandan los tuyos;
  si no, se usan los medidos con 2 o más entregas.

## Instalar

Direcciones del flujo: página `/webhook/planeador-compras` y API `/webhook/planeador-compras-api`
(no chocan con ningún otro flujo).

1. En n8n: **Importar desde archivo** → `n8n/Planeador de compras (Microsip).json`.
2. Revisa que los nodos Postgres usen la credencial **Postgres account** (la misma de los demás flujos).
3. Activa el flujo.
4. Abre el nodo **Ver ligas** y ejecútalo. Te da tres ligas:
   - `compras`: para capturar.
   - `auditor`: solo consulta, para enseñarla en la auditoría.
   - `administrador`: la misma llave del tablero.

## Primer uso

1. **Configuración → Proveedores**: pon los días de entrega de cada proveedor (CEMEX, Grupo Acerero, Ferremax, Truper…), aunque sea aproximado, y qué día revisas sus productos A. Guarda.
2. **A/B/C y máximos-mínimos → Recalcular este mes.**
3. **Registro de compras** → mes de agosto → **Reconstruir desde Microsip**. Repite con septiembre.
   Solo llena la razón donde compraste distinto al sugerido. La razón tiene que ser la verdadera: si no te acuerdas, elige **No documentado**.
4. En **Validar contra el Diario de compras**, pon del 1 de agosto al 30 de septiembre y compara con el reporte de Microsip:
   según el Diario del 6 de octubre deben salir **9 órdenes** (O62, O64, O65, O66, O67, O72, O73, O74 y O76) con
   **$151,944.47** de importe neto y **$176,255.59** con IVA.
5. De octubre en adelante: usa el **Planeador** el día que toca, guarda y captura la OC en Microsip. La página la reconoce sola
   (mismo proveedor, dentro de 7 días) o por el folio que escribas.

## Para que el servidor no se cargue

- Cada acción de la página es **una sola consulta** a Postgres, sin compilación JIT, con límite de tiempo (`statement_timeout`) y de espera
  por bloqueo, así que nunca se queda pegada ni frena los otros flujos.
- Los máximos y mínimos se calculan **una vez al mes** y se guardan (`compras_maxmin`). La página solo lee lo ya calculado.
- El flujo **no guarda en el historial de n8n** las ejecuciones que salen bien (solo los errores).
- El Excel se arma en el navegador, no en el servidor.
- Con datos de prueba de 5,000 artículos y 400,000 renglones de venta: cálculo del mes ≈ 1 s, reconstruir un mes ≈ 2 s,
  abrir la página ≈ 0.2 s.

## Cómo se calcula lo de agosto y septiembre

- **Órdenes de compra**: documentos de compras tipo `O` en `DOCTOS_CM` / `DOCTOS_CM_DET` (sin canceladas).
- **Existencia del día de la OC**, en este orden:
  1. la foto diaria del inventario (`ms_existencias_hist`, si el flujo “Historial de inventario diario” estaba prendido);
  2. si no, existencia de hoy menos los movimientos desde ese día (`RESUMEN_MOVTOS_IN`, si trae unidades);
  3. si no, existencia de hoy menos ventas y compras desde ese día (aproximado: no cuenta ajustes ni traspasos).
  Cada renglón dice qué método se usó.
- **Por recibir**: otras OCs del mismo artículo hechas en los días de entrega anteriores.
- **Máximos/mínimos**: los del mes de la OC, calculados con los 6 meses anteriores a ese mes.

**Por recibir hoy** = lo que falta de cada OC (pedido − recibido por `DOCTOS_CM_LIGAS`) mientras no pase de (días de entrega + 5) días,
o si confirmaste que sigue en camino. Se revisan las OCs del último año (Microsip cuenta todas las pendientes). Si la copia de Microsip trae
`UNIDADES_REC_DEV` en el renglón de la OC, manda lo que dice Microsip. Solo para OCs que **nunca** se ligaron (y sin ese dato), una recepción
capturada sin ligar del mismo proveedor y artículo cuenta como recibido; en Seguimiento sale como «sin ligar».
En «Ver cálculo» → **Órdenes de compra de este producto** se ve cada OC con el estatus de Microsip, lo pedido, lo recibido (ligado / Microsip /
sin ligar) y lo que falta, para comparar con «Por recibir» de Microsip.

En el planeador, los contadores de cada proveedor (Críticos, Por pedir, Próximos, Bien, Revisar) son filtros, y en «Ver cálculo» se cambia el
proveedor del producto (cuenta de inmediato).

## Tablas que crea

`compras_config`, `compras_proveedores`, `compras_articulos`, `compras_maxmin` (foto mensual A/B y máx/mín),
`compras_planes` y `compras_decisiones` (registro de compras), `compras_equivalencias`, `compras_politica`, `compras_oc_seguimiento`,
`compras_revision` y `ms_existencias_hist` (foto diaria). No modifica ninguna tabla de Microsip.

## Para cambiar algo

Los archivos fuente están en `pagina.html`, `sql/*.sql` y `n8n/*.js`. Después de editar:

```bash
python3 compras/armar_flujo.py          # vuelve a generar el JSON del flujo
python3 compras/pruebas/probar_todo.py  # pruebas contra un Postgres local (ver pruebas/datos_prueba.py)
```
