-- Módulo 3: productos de un proveedor con existencia, pendiente por recibir, mínimo, máximo y sugerido. p = {proveedor_id}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*OC*/,
ms AS (SELECT max(mes) AS mes FROM compras_maxmin, cfg WHERE compras_maxmin.base = cfg.base AND mes <= cfg.hoy),
mm0 AS (SELECT x.articulo_id, x.clave, x.articulo, x.unidad, x.clase, x.venta_diaria, x.minimo, x.maximo, x.alerta, x.empaque
        FROM compras_maxmin x, cfg, ms WHERE x.base = cfg.base AND x.mes = ms.mes
         AND coalesce(x.proveedor_id, '') = coalesce(cfg.p->>'proveedor_id', '')),
/*EXCL*/,
nv AS (   -- vendidos desde que se calculó el mes y que no estaban en la lista (productos nuevos): entran como C provisional
  SELECT d.articulo_id, sum(CASE WHEN upper(v.tipo) = 'D' THEN -1 ELSE 1 END * abs(d.unidades)) AS u
  FROM ms_ventas v JOIN ms_ventas_det d ON d.base = v.base AND d.origen = v.origen AND d.docto_id = v.docto_id, cfg, ms
  WHERE v.base = cfg.base AND v.fecha >= ms.mes AND coalesce(v.estatus, '') <> 'C' AND d.articulo_id IS NOT NULL
    AND ((v.origen = 'PV' AND upper(v.tipo) IN ('V', 'D')) OR (v.origen = 'VE' AND v.tipo = 'R'))
    AND NOT EXISTS (SELECT 1 FROM compras_maxmin x WHERE x.base = cfg.base AND x.mes = ms.mes AND x.articulo_id = d.articulo_id)
    AND NOT EXISTS (SELECT 1 FROM excl WHERE excl.articulo_id = d.articulo_id)
  GROUP BY 1 HAVING sum(CASE WHEN upper(v.tipo) = 'D' THEN -1 ELSE 1 END * abs(d.unidades)) > 0),
nvc AS (  -- proveedor de la última compra de esos artículos
  SELECT DISTINCT ON (z.articulo_id) z.articulo_id, z.prov FROM (
    SELECT (d.datos->>'ARTICULO_ID')::bigint AS articulo_id, r.datos->>'PROVEEDOR_ID' AS prov, coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) AS fecha
    FROM ms_raw d JOIN cfg ON d.base = cfg.base
    JOIN ms_raw r ON r.base = d.base AND r.tabla = 'DOCTOS_CM' AND r.datos->>'DOCTO_CM_ID' = d.datos->>'DOCTO_CM_ID'
    WHERE d.tabla = 'DOCTOS_CM_DET' AND (d.datos->>'ARTICULO_ID') ~ '^[0-9]+$' AND (SELECT count(*) FROM nv) > 0
      AND (d.datos->>'ARTICULO_ID')::bigint IN (SELECT articulo_id FROM nv)
      AND upper(coalesce(r.datos->>'TIPO_DOCTO', '')) IN ('O', 'R', 'C') AND upper(coalesce(r.datos->>'ESTATUS', '')) <> 'C') z
  ORDER BY z.articulo_id, z.fecha DESC),
nv2 AS (
  SELECT nv.articulo_id, a.clave, a.nombre AS articulo, a.unidad, nv.u / greatest(cfg.hoy - ms.mes + 1, 1) AS vd,
         coalesce(cp.dias_entrega, cfg.ent_def) AS ent, ov.minimo AS min_f, ov.maximo AS max_f, ov.empaque
  FROM nv CROSS JOIN cfg CROSS JOIN ms
  LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = nv.articulo_id
  LEFT JOIN compras_articulos ov ON ov.base = cfg.base AND ov.articulo_id = nv.articulo_id
  LEFT JOIN nvc ON nvc.articulo_id = nv.articulo_id
  LEFT JOIN compras_proveedores cp ON cp.base = cfg.base AND cp.proveedor_id = coalesce(nullif(ov.proveedor_id, ''), nvc.prov)
  WHERE coalesce(nullif(ov.proveedor_id, ''), nvc.prov, '') = coalesce(cfg.p->>'proveedor_id', '')),
nv3 AS (SELECT nv2.*, greatest(coalesce(nv2.min_f, ceil(nv2.vd * (nv2.ent + cfg.seg_c))), cfg.min_c) AS mn FROM nv2, cfg),
mm AS (SELECT * FROM mm0
       UNION ALL
       SELECT nv3.articulo_id, nv3.clave, nv3.articulo, nv3.unidad, 'C', round(nv3.vd, 4), nv3.mn,
              greatest(coalesce(nv3.max_f, nv3.mn + ceil(nv3.vd * cfg.inv_c)), nv3.mn + 1),
              'nuevo: se vendió este mes y aún no tiene clase (entra como C hasta el próximo cálculo)', nv3.empaque
       FROM nv3, cfg),
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
