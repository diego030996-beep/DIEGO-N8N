# Producción de tinacos (Microsip → n8n)

Página para capturar lo que se fabrica, sacar la materia prima del inventario con su receta, saber el costo y la utilidad de cada tinaco
y bajar cada semana los archivos para importarlos en Microsip. Lee las mismas tablas de Microsip que ya se copian a Postgres
(`ms_articulos`, `ms_existencias`, `ms_raw`) y **no modifica ninguna**.

| Pestaña | Qué hace |
|---|---|
| Capturar producción | "Hoy se hicieron 10 TINACO 1100 NEGRO": calcula el polímero, tapas y kits que salen, su costo y avisa si no alcanza |
| Recetas | Qué sale del inventario por cada tinaco (polímero en kg, tapa, kit…), eligiendo artículos de Microsip. Se copia a otro color cambiando el polímero |
| Simulación y utilidad | Precio **distribuidor, público y Mercado Libre** (comisión, cargo fijo, envío y retenciones de ISR e IVA) − (materiales + mano de obra, gas, luz, etiquetas) = utilidad y margen; los precios se guardan. "¿Qué pasa si sube el polímero?" y "si fabrico N, qué me falta comprar" |
| Semana: archivos Microsip | Dos `.txt` (`CLAVE,UNIDADES,COSTO`, sin encabezado): **salida de materia prima** y **entrada de tinacos** al costo de sus materiales |
| Auditoría de polímero | Lo que **debe haber** (último pesaje + entradas de Microsip − consumo de recetas) contra lo que **hay** en la báscula; diferencia en kg y $, cuánto es por tinacos más pesados que la receta y cuánto es merma; alerta para volver a pesar; ajuste por merma para Microsip |
| Materia prima | Lo que entró (recepciones/compras de Microsip), lo que se consumió, lo que hay y para cuántos días alcanza |
| Cuánto se hizo | Tinacos por semana (12) y por modelo, con costo |

Cómo cuenta:

- **Costo del tinaco** = suma de su receta × último costo de Microsip (si no tiene, el precio de su última compra). Se guarda en cada captura,
  así que si después cambia la receta o el costo, lo ya capturado no cambia.
- **Mano de obra, gas, luz, etiquetas** solo entran a la simulación (no salen del inventario ni del costo; ya van en la tabla de gastos).
- **Disponible** = existencia de Microsip − lo capturado que todavía no se importa en Microsip. Al bajar los archivos se marcan como exportados
  (no vuelven a salir); cuando ya los importaste, pulsa «Ya lo importé en Microsip» y la página deja de descontarlos aparte.
- Cada color es un artículo distinto en Microsip: cada uno lleva su receta (se copia de otro y se cambia el polímero).

## Auditoría de polímero

1. **Pesaje inicial**: el primer pesaje es el punto de partida.
2. Cada pesaje después calcula **debe haber** = pesaje anterior + lo que entró en Microsip (recepciones, compras que no vienen de recepción,
   menos devoluciones) − lo que consumieron las recetas de lo capturado. El pesaje cuenta al **cierre del día** (si el mismo día se captura
   producción después de un pesaje, cuenta para el siguiente).
3. Si la diferencia pasa la tolerancia (5 kg o 2 % de lo consumido, lo que sea mayor; se cambia en Configuración) sale la **alerta "vuelve a
   pesar"** en toda la página. El nuevo pesaje confirma y reemplaza al anterior.
4. **¿Más polímero o merma? (predicción, sin pesar tinacos)**: con 3 o más pesajes se ajusta *lo que falta = kg por tinaco × tinacos + kg fijos*.
   La parte que crece con los tinacos es **exceso al llenar**; la fija es **merma** (purga, rebaba, desperdicio…). Usa los pesajes desde el
   último ajuste (si hay menos de 3, los últimos 12 del historial). Si además se anota el **peso real** de algunos tinacos, se separa exacto.
5. **Fin de semana**: las diferencias confirmadas se bajan como **ajuste por merma** (`CLAVE,KG,COSTO`: salida si faltó, entrada si sobró) para
   importarlo en Microsip. El ajuste **cierra el periodo**: las estadísticas empiezan de cero y el historial de ajustes se queda.
6. **Ligar el folio de Microsip**: al marcar «Ya lo importé» (producción o merma) la página busca en la copia de Microsip (`RESUMEN_MOVTOS_IN`,
   movimientos de inventario) el documento con esos artículos y sugiere su folio; también se puede escribir a mano.

**Hoja para el quemador**: en Recetas, «🖨️ Hoja para el quemador» abre una tabla para imprimir con los kg de polímero de cada tinaco.

## Instalar

1. En n8n: **Importar desde archivo** → `n8n/Producción de tinacos (Microsip).json`. Credencial **Postgres account** (la misma de los demás).
2. Activa el flujo. Direcciones: `/webhook/produccion-tinacos` y `/webhook/produccion-tinacos-api` (no chocan con otros flujos).
3. Ejecuta el nodo **Ver ligas**: da la liga `produccion` (captura), `auditor` (solo consulta) y `administrador`.
4. Primer uso: **Recetas** → arma la de cada tinaco (o una y cópiala a los demás colores). Luego **Capturar producción** cada día y
   **Semana** para bajar los archivos.

Tablas que crea: `prod_config`, `prod_receta`, `prod_extra`, `prod_precio`, `prod_registro`, `prod_registro_det`, `prod_exporte`, `prod_conteo` (pesajes), `prod_ajuste` (merma).

## Para cambiar algo

```bash
python3 produccion/armar_flujo.py          # vuelve a generar el JSON del flujo
python3 produccion/pruebas/probar_todo.py       # pruebas contra el Postgres local (crea sus datos con pruebas/datos_prueba.py)
python3 produccion/pruebas/probar_auditoria.py  # auditoría de polímero y merma
```
