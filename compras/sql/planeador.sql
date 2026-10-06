-- Módulo 3: productos de un proveedor con existencia, pendiente por recibir, mínimo, máximo y sugerido. p = {proveedor_id}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*OC*/,
ms AS (SELECT max(mes) AS mes FROM compras_maxmin, cfg WHERE compras_maxmin.base = cfg.base AND mes <= cfg.hoy),
mm AS (SELECT x.* FROM compras_maxmin x, cfg, ms WHERE x.base = cfg.base AND x.mes = ms.mes
         AND coalesce(x.proveedor_id, '') = coalesce(cfg.p->>'proveedor_id', '')),
ids AS (SELECT id FROM oc, cfg WHERE oc.fecha >= cfg.hoy - 120), /*OCD*/, /*EXI*/,
pl AS (SELECT pl.* FROM compras_planes pl, cfg WHERE pl.base = cfg.base AND pl.fecha = cfg.hoy AND pl.origen = 'planeador'
         AND pl.proveedor_id = cfg.p->>'proveedor_id'),
dec AS (SELECT d.* FROM compras_decisiones d JOIN pl ON pl.id = d.plan_id),
uc AS (  -- última OC del artículo con este proveedor
  SELECT DISTINCT ON (d.articulo_id) d.articulo_id, o.fecha, d.u FROM oc o JOIN ocd d ON d.id = o.id, cfg
  WHERE o.prov = cfg.p->>'proveedor_id' ORDER BY d.articulo_id, o.fecha DESC),
f AS (
  SELECT mm.articulo_id, mm.clave, mm.articulo, mm.unidad, mm.clase, mm.venta_diaria, mm.minimo, mm.maximo, mm.alerta,
         coalesce(ov.empaque, mm.empaque) AS empaque, coalesce(exi.e, 0) AS existencia, coalesce(pend.u, 0) AS pendiente, pend.folios,
         uc.fecha AS ult_fecha, uc.u AS ult_unidades
  FROM mm CROSS JOIN cfg
  LEFT JOIN compras_articulos ov ON ov.base = cfg.base AND ov.articulo_id = mm.articulo_id
  LEFT JOIN exi ON exi.articulo_id = mm.articulo_id LEFT JOIN pend ON pend.articulo_id = mm.articulo_id
  LEFT JOIN uc ON uc.articulo_id = mm.articulo_id),
g AS (SELECT f.*, /*SUG(f.existencia, f.pendiente, f.minimo, f.maximo, f.empaque)*/ AS sugerido FROM f, cfg)
SELECT json_build_object('ok', true, 'mes', (SELECT mes FROM ms)::text, 'proveedor_id', cfg.p->>'proveedor_id', 'regla', cfg.regla,
  'plan', (SELECT json_build_object('id', id, 'folio', folio, 'folio_oc', folio_oc, 'clase', clase, 'creado', creado, 'modificado', modificado) FROM pl LIMIT 1),
  'filas', (SELECT coalesce(json_agg(json_build_object(
      'articulo_id', g.articulo_id, 'clave', g.clave, 'articulo', g.articulo, 'unidad', g.unidad, 'clase', g.clase,
      'vd', round(g.venta_diaria, 2), 'minimo', g.minimo, 'maximo', g.maximo, 'empaque', g.empaque, 'alerta', g.alerta,
      'existencia', g.existencia, 'pendiente', g.pendiente, 'folios', g.folios, 'sugerido', g.sugerido,
      'ult_fecha', g.ult_fecha, 'ult_unidades', g.ult_unidades,
      'comprado', dec.comprado, 'razon', dec.razon, 'nota', dec.nota)
      ORDER BY g.clase, (g.sugerido > 0) DESC, (greatest(g.existencia, 0) + g.pendiente) / nullif(g.minimo, 0), g.articulo), '[]'::json)
    FROM g LEFT JOIN dec USING (articulo_id))) AS r
FROM cfg;
