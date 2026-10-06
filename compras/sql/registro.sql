-- Módulo 5 / evidencia: registro del mes (planes con sus decisiones y su OC) + OCs del mes sin plan. p = {mes}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*OC*/,
m AS (SELECT date_trunc('month', coalesce(nullif(p->>'mes', '')::date, hoy))::date AS mes FROM cfg),
ids AS (SELECT o.id FROM oc o, m WHERE o.fecha >= m.mes AND o.fecha < (m.mes + interval '1 month')::date), /*OCD*/, /*EXCL*/,
solo_excl AS (SELECT ocd.id FROM ocd GROUP BY ocd.id HAVING bool_and(ocd.articulo_id IN (SELECT articulo_id FROM excl))),
pl AS (SELECT pl.* FROM compras_planes pl, cfg, m WHERE pl.base = cfg.base
         AND coalesce(pl.fecha_oc, pl.fecha) >= m.mes AND coalesce(pl.fecha_oc, pl.fecha) < (m.mes + interval '1 month')::date),
arts AS (SELECT DISTINCT d.articulo_id FROM compras_decisiones d JOIN pl ON pl.id = d.plan_id),
upc AS MATERIALIZED (  -- precio de la última compra (para los artículos sin último costo en Microsip)
  SELECT DISTINCT ON (z.articulo_id) z.articulo_id, z.precio FROM (
    SELECT (CASE WHEN (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z' THEN (d.datos->>'ARTICULO_ID')::bigint END) AS articulo_id,
           CASE WHEN (d.datos->>'PRECIO_UNITARIO') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'PRECIO_UNITARIO')::numeric END AS precio,
           coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) AS fecha
    FROM ms_raw d JOIN cfg ON d.base = cfg.base
    JOIN ms_raw r ON r.base = d.base AND r.tabla = 'DOCTOS_CM' AND r.datos->>'DOCTO_CM_ID' = d.datos->>'DOCTO_CM_ID'
    WHERE d.tabla = 'DOCTOS_CM_DET' AND upper(coalesce(r.datos->>'TIPO_DOCTO', '')) IN ('O', 'R', 'C')
      AND upper(coalesce(r.datos->>'ESTATUS', '')) <> 'C') z
  WHERE z.articulo_id IN (SELECT articulo_id FROM arts) AND z.precio > 0
  ORDER BY z.articulo_id, z.fecha DESC)
SELECT json_build_object('ok', true, 'mes', (SELECT mes FROM m)::text, 'razones', cfg.c->>'razones',
  'planes', (SELECT coalesce(json_agg(json_build_object(
       'id', pl.id, 'fecha', pl.fecha, 'proveedor_id', pl.proveedor_id, 'proveedor', coalesce(pl.proveedor, prv.nombre), 'clase', pl.clase,
       'origen', pl.origen, 'folio', pl.folio, 'folio_oc', pl.folio_oc, 'fecha_oc', pl.fecha_oc, 'por', pl.por, 'creado', pl.creado,
       'lineas', (SELECT coalesce(json_agg(json_build_object('id', d.id, 'articulo_id', d.articulo_id, 'clave', coalesce(a.clave, d.clave), 'articulo', d.articulo,
                    'costo', coalesce(nullif(a.costo_ultimo, 0), upc.precio),
                    'costo_fuente', CASE WHEN nullif(a.costo_ultimo, 0) IS NOT NULL THEN 'último costo' WHEN upc.precio IS NOT NULL THEN 'última compra' END,
                    'unidad', d.unidad, 'clase', d.clase, 'existencia', d.existencia, 'pendiente', d.pendiente, 'minimo', d.minimo, 'punto_reorden', d.punto_reorden,
                    'maximo', d.maximo, 'sugerido', d.sugerido, 'comprado', d.comprado, 'oc_unidades', d.oc_unidades, 'razon', d.razon,
                    'nota', d.nota, 'fuente', d.fuente, 'por', d.por, 'modificado', coalesce(d.modificado, d.creado)) ORDER BY d.clase, d.articulo), '[]'::json)
                  FROM compras_decisiones d
                  LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = d.articulo_id
                  LEFT JOIN upc ON upc.articulo_id = d.articulo_id
                  WHERE d.plan_id = pl.id))
     ORDER BY coalesce(pl.fecha_oc, pl.fecha), pl.id), '[]'::json) FROM pl LEFT JOIN prv ON prv.proveedor_id = pl.proveedor_id),
  'oc_sin_plan', (SELECT coalesce(json_agg(json_build_object('id', o.id, 'folio', o.folio, 'fecha', o.fecha, 'proveedor', prv.nombre,
       'importe', o.importe) ORDER BY o.fecha), '[]'::json)
     FROM oc o CROSS JOIN m LEFT JOIN prv ON prv.proveedor_id = o.prov
     WHERE o.fecha >= m.mes AND o.fecha < (m.mes + interval '1 month')::date
       AND o.id NOT IN (SELECT id FROM solo_excl)
       AND NOT EXISTS (SELECT 1 FROM compras_planes q WHERE q.base = cfg.base AND q.docto_cm_id = o.id))) AS r
FROM cfg;
