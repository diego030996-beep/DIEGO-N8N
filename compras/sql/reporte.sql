-- Lista A/B/C y máximos/mínimos de un mes (para ver y exportar). p = {mes}
-- Para que pese poco: las filas van como listas de valores, con los nombres de columna una sola vez en "cols".
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/,
m AS (SELECT coalesce(date_trunc('month', nullif(p->>'mes', '')::date)::date,
                      (SELECT max(mes) FROM compras_maxmin x WHERE x.base = cfg.base AND x.mes <= cfg.hoy)) AS mes FROM cfg),
x AS (SELECT x.* FROM compras_maxmin x, cfg, m WHERE x.base = cfg.base AND x.mes = m.mes)
SELECT json_build_object('ok', true, 'mes', (SELECT mes FROM m)::text,
  'calculado', (SELECT max(calculado) FROM x),
  'periodos', (SELECT json_object_agg(c, json_build_object('ini', ini, 'fin', fin, 'dias', dias)) FROM (
       SELECT CASE WHEN clase = 'C' THEN 'C' ELSE 'AB' END AS c, min(periodo_ini) AS ini, max(periodo_fin) AS fin, max(dias_periodo) AS dias
       FROM x GROUP BY 1) z),
  'cols', json_build_array('articulo_id', 'clave', 'articulo', 'unidad', 'proveedor_id', 'proveedor', 'clase', 'venta', 'unidades', 'pct', 'pct_acum',
       'vd', 'entrega', 'seguridad', 'inventario', 'empaque', 'minimo', 'maximo', 'punto_reorden', 'rotacion', 'semanas_venta', 'semanas', 'tickets',
       'sd', 'ns', 'revision', 'metodo', 'origen', 'alerta'),
  'filas', (SELECT coalesce(json_agg(json_build_array(x.articulo_id, x.clave, x.articulo, x.unidad, x.proveedor_id, x.proveedor, x.clase, x.venta,
       x.unidades, x.pct, x.pct_acum, x.venta_diaria, x.dias_entrega, x.dias_seguridad, x.dias_inventario, x.empaque, x.minimo, x.maximo,
       coalesce(x.punto_reorden, x.minimo), x.rotacion, x.semanas_venta, x.semanas, x.tickets, x.desv_diaria, x.nivel_servicio, x.dias_revision,
       x.metodo, x.origen, x.alerta) ORDER BY x.venta DESC), '[]'::json) FROM x)) AS r
FROM cfg;
