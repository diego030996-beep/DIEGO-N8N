# Planeador de compras (Microsip → n8n)

Página web para comprar con máximos y mínimos y dejar la evidencia lista para el auditor. Funciona como las otras
páginas: un flujo de n8n que lee las tablas de Microsip que ya se copian a Postgres (`ms_*` y `ms_raw`).

| Pestaña | Qué hace | Lineamiento |
|---|---|---|
| A/B/C y máximos-mínimos | Cada mes (día 1, 3:40 a.m.) calcula el 80/20 con la venta de los últimos 6 meses, los C y los máximos/mínimos | 1.2.1.1 · 1.2.2.2 |
| Planeador | Según el calendario (A cada semana, B y C cada 15 días por proveedor) muestra existencia, por recibir, mínimo, máximo y sugerido. Capturas lo que compras y la razón si es distinto | 1.2.2.3 · 1.2.2.4 |
| Registro de compras | Liga cada plan con su orden de compra de Microsip (sola o por folio), reconstruye meses pasados y exporta el registro mensual | 1.3.1.1 |
| Configuración | Todas las reglas, los proveedores, los ajustes por artículo y la lista de razones. **Todo se guarda en la base de datos** | — |

Cómo se clasifica (se explica también en la página y en el Excel):

- **A**: los artículos que juntos suman el primer **80%** de la venta (importe sin IVA) de los últimos **6 meses**
  completos. Cuentan tickets de punto de venta menos devoluciones y remisiones; no cuentan cancelados ni tickets de más de $500,000.
- **B**: el resto de los que se vendieron en esos 6 meses.
- **C**: los que se vendieron en los últimos **12 meses** pero no en esos 6, y los que se venden por primera vez en el mes
  (entran como C provisional en el planeador hasta el siguiente cálculo). No cuentan para el 80/20.
- **No entran**: las líneas o grupos de Microsip que digan `tinaco|cisterna` (fabricación propia), los dados de baja y los
  marcados a mano. La página lo avisa y sus OCs no salen como pendientes en el registro.

Mínimo, punto de reorden y máximo (método recomendado; se cambia en la página):

- **Mínimo (stock de seguridad)** = Z × variación de la venta diaria × √(días de entrega + días entre revisiones).
  Z sale del nivel de servicio: A 95 % (1.65), B 90 % (1.28), C 85 % (1.04). La variación se mide semana por semana.
- **Punto de reorden** = venta diaria × (días de entrega + días entre revisiones) + mínimo. Cuando existencia + por recibir
  llega aquí, se pide. Revisión: A cada 7 días, B y C cada 15.
- **Máximo** = punto de reorden + venta diaria × días de inventario (A 7, B 15, C 30). El sugerido es máximo − existencia − por recibir,
  redondeado al empaque.
- **Rotación** = % de semanas con venta: mucho ≥ 50 %, medio ≥ 20 %, poco abajo. Los que rotan poco no llevan colchón por variación:
  mínimo 1, punto de reorden 1 y máximo 2 (o lo que dé su venta).
- Ninguno queda en 0 y siempre máximo > punto de reorden ≥ mínimo. También está el **método simple**
  (mínimo = venta diaria × (entrega + días de seguridad)) por si el auditor pide ese.

Planeador: vista **Por proveedor** o **Todos los productos** (todo lo que hay que pedir, agrupado por proveedor; "Guardar todo"
guarda un plan por proveedor).

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

- Cada acción de la página es **una sola consulta** a Postgres, con límite de tiempo (`statement_timeout`) y de espera
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

**Por recibir hoy** = OCs sin recepción ligada (`DOCTOS_CM_LIGAS`) y con menos de (días de entrega + 5) días.

## Tablas que crea

`compras_config`, `compras_proveedores`, `compras_articulos`, `compras_maxmin` (foto mensual A/B y máx/mín),
`compras_planes` y `compras_decisiones` (registro de compras). No modifica ninguna tabla de Microsip.

## Para cambiar algo

Los archivos fuente están en `pagina.html`, `sql/*.sql` y `n8n/*.js`. Después de editar:

```bash
python3 compras/armar_flujo.py          # vuelve a generar el JSON del flujo
python3 compras/pruebas/probar_todo.py  # pruebas contra un Postgres local (ver pruebas/datos_prueba.py)
```
