-- Módulo 5 / evidencia: registro del mes (planes con sus decisiones y su OC) + OCs del mes sin plan. p = {mes}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*OC*/,
m AS (SELECT date_trunc('month', coalesce(nullif(p->>'mes', '')::date, hoy))::date AS mes FROM cfg),
pl AS (SELECT pl.* FROM compras_planes pl, cfg, m WHERE pl.base = cfg.base
         AND coalesce(pl.fecha_oc, pl.fecha) >= m.mes AND coalesce(pl.fecha_oc, pl.fecha) < (m.mes + interval '1 month')::date)
SELECT json_build_object('ok', true, 'mes', (SELECT mes FROM m)::text, 'razones', cfg.c->>'razones',
  'planes', (SELECT coalesce(json_agg(json_build_object(
       'id', pl.id, 'fecha', pl.fecha, 'proveedor_id', pl.proveedor_id, 'proveedor', coalesce(pl.proveedor, prv.nombre), 'clase', pl.clase,
       'origen', pl.origen, 'folio', pl.folio, 'folio_oc', pl.folio_oc, 'fecha_oc', pl.fecha_oc, 'por', pl.por, 'creado', pl.creado,
       'lineas', (SELECT coalesce(json_agg(json_build_object('id', d.id, 'articulo_id', d.articulo_id, 'clave', d.clave, 'articulo', d.articulo,
                    'unidad', d.unidad, 'clase', d.clase, 'existencia', d.existencia, 'pendiente', d.pendiente, 'minimo', d.minimo,
                    'maximo', d.maximo, 'sugerido', d.sugerido, 'comprado', d.comprado, 'oc_unidades', d.oc_unidades, 'razon', d.razon,
                    'nota', d.nota, 'fuente', d.fuente, 'por', d.por, 'modificado', coalesce(d.modificado, d.creado)) ORDER BY d.clase, d.articulo), '[]'::json)
                  FROM compras_decisiones d WHERE d.plan_id = pl.id))
     ORDER BY coalesce(pl.fecha_oc, pl.fecha), pl.id), '[]'::json) FROM pl LEFT JOIN prv ON prv.proveedor_id = pl.proveedor_id),
  'oc_sin_plan', (SELECT coalesce(json_agg(json_build_object('id', o.id, 'folio', o.folio, 'fecha', o.fecha, 'proveedor', prv.nombre,
       'importe', o.importe) ORDER BY o.fecha), '[]'::json)
     FROM oc o CROSS JOIN m LEFT JOIN prv ON prv.proveedor_id = o.prov
     WHERE o.fecha >= m.mes AND o.fecha < (m.mes + interval '1 month')::date
       AND NOT EXISTS (SELECT 1 FROM compras_planes q WHERE q.base = cfg.base AND q.docto_cm_id = o.id))) AS r
FROM cfg;
