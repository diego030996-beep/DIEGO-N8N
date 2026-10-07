-- Seguimiento: órdenes de compra abiertas, parciales y atrasadas (con lo que falta por renglón) y planes guardados que no son OC.
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*OC*/,
ids AS (SELECT id FROM oc, cfg WHERE oc.fecha >= cfg.hoy - 180), /*OCD*/, /*EQV*/, /*LT*/, /*EXI*/,
segx AS (SELECT s.* FROM compras_oc_seguimiento s, cfg WHERE s.base = cfg.base),
abiertas AS (
  SELECT l.id, max(l.folio) AS folio, max(l.fecha) AS fecha, max(l.prov) AS prov, max(l.lt) AS lt,
         CASE WHEN bool_or(l.estado = 'atrasada') THEN 'atrasada' WHEN bool_or(l.estado = 'atrasada_confirmada') THEN 'en_camino'
              WHEN bool_or(l.estado = 'parcial') OR (sum(l.recibido) > 0) THEN 'parcial' ELSE 'abierta' END AS estado,
         sum(l.pedido) AS pedido, sum(l.recibido) AS recibido, sum(l.falta) AS falta,
         json_agg(json_build_object('articulo_id', l.articulo_id, 'clave', a.clave, 'articulo', a.nombre, 'unidad', a.unidad,
                  'pedido', l.pedido, 'recibido', l.recibido, 'sin_ligar', l.rec_suelto, 'falta', l.falta) ORDER BY a.nombre) AS lineas
  FROM ocl l CROSS JOIN cfg LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = l.articulo_id
  WHERE l.estado NOT IN ('cerrada', 'completa') GROUP BY l.id),
planes AS (
  SELECT pl.id, pl.fecha, pl.proveedor_id, coalesce(pl.proveedor, prv.nombre) AS proveedor, pl.folio, pl.por,
         count(d.*) FILTER (WHERE d.comprado > 0) AS renglones, sum(d.comprado) AS unidades
  FROM compras_planes pl JOIN compras_decisiones d ON d.plan_id = pl.id CROSS JOIN cfg LEFT JOIN prv ON prv.proveedor_id = pl.proveedor_id
  WHERE pl.base = cfg.base AND pl.origen = 'planeador' AND pl.docto_cm_id IS NULL AND pl.fecha >= cfg.hoy - 30
  GROUP BY pl.id, prv.nombre HAVING sum(d.comprado) > 0)
SELECT json_build_object('ok', true, 'hoy', cfg.hoy::text,
  'ocs', (SELECT coalesce(json_agg(json_build_object('id', o.id, 'folio', o.folio, 'fecha', o.fecha, 'dias', cfg.hoy - o.fecha, 'lt', o.lt,
            'proveedor_id', o.prov, 'proveedor', prv.nombre, 'estado', o.estado, 'pedido', o.pedido, 'recibido', o.recibido, 'falta', o.falta,
            'seguimiento', s.estado, 'nota', s.nota, 'por', s.por, 'lineas', o.lineas)
          ORDER BY CASE o.estado WHEN 'atrasada' THEN 0 WHEN 'en_camino' THEN 1 WHEN 'parcial' THEN 2 ELSE 3 END, o.fecha), '[]'::json)
          FROM abiertas o LEFT JOIN prv ON prv.proveedor_id = o.prov LEFT JOIN segx s ON s.docto_cm_id = o.id),
  'planes', (SELECT coalesce(json_agg(planes ORDER BY planes.fecha), '[]'::json) FROM planes),
  'proveedores_lt', (SELECT coalesce(json_agg(json_build_object('proveedor_id', ltp.prov, 'proveedor', prv.nombre, 'manual', ltp.manual,
            'medido', ltp.medido, 'peor', ltp.peor, 'entregas', ltp.n, 'usa', coalesce(ltp.dias, cfg.ent_def)) ORDER BY prv.nombre), '[]'::json)
          FROM ltp LEFT JOIN prv ON prv.proveedor_id = ltp.prov)) AS r
FROM cfg;
