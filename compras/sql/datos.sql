-- Al abrir la página: crea tablas si faltan, liga OCs nuevas y regresa el resumen (proveedores, calendario, pendientes).
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '5s';
/*ESQUEMA*/
/*LIGAR*/
WITH /*CTX*/, /*OC*/,
ms AS (SELECT max(mes) AS mes FROM compras_maxmin, cfg WHERE compras_maxmin.base = cfg.base AND mes <= cfg.hoy),
mm AS (SELECT x.* FROM compras_maxmin x, cfg, ms WHERE x.base = cfg.base AND x.mes = ms.mes),
ids AS (SELECT id FROM oc, cfg WHERE oc.fecha >= cfg.hoy - 120), /*OCD*/, /*EXI*/,
est AS (SELECT mm.proveedor_id, count(*) FILTER (WHERE mm.clase = 'A') AS n_a, count(*) FILTER (WHERE mm.clase = 'B') AS n_b,
               count(*) FILTER (WHERE mm.clase = 'A' AND greatest(coalesce(exi.e, 0), 0) + coalesce(pend.u, 0) <= mm.minimo) AS bajo_a,
               count(*) FILTER (WHERE mm.clase = 'B' AND greatest(coalesce(exi.e, 0), 0) + coalesce(pend.u, 0) <= mm.minimo) AS bajo_b,
               max(mm.proveedor) AS nombre
        FROM mm LEFT JOIN exi USING (articulo_id) LEFT JOIN pend USING (articulo_id) GROUP BY 1),
ult AS (SELECT pl.proveedor_id, max(pl.fecha) FILTER (WHERE pl.clase LIKE '%A%') AS ult_a, max(pl.fecha) FILTER (WHERE pl.clase LIKE '%B%') AS ult_b
        FROM compras_planes pl, cfg WHERE pl.base = cfg.base AND pl.origen = 'planeador' GROUP BY 1),
recientes AS (SELECT DISTINCT r.datos->>'PROVEEDOR_ID' AS proveedor_id FROM ms_raw r, cfg
              WHERE r.base = cfg.base AND r.tabla = 'DOCTOS_CM' AND coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) >= cfg.hoy - 365),
todos AS (SELECT proveedor_id FROM est WHERE proveedor_id IS NOT NULL
          UNION SELECT proveedor_id FROM compras_proveedores, cfg WHERE compras_proveedores.base = cfg.base
          UNION SELECT proveedor_id FROM recientes WHERE proveedor_id IS NOT NULL),
pv AS (
  SELECT t.proveedor_id, coalesce(nullif(cp.nombre, ''), prv.nombre, est.nombre, 'Proveedor ' || t.proveedor_id) AS nombre,
         cp.dias_entrega, cp.dia_a, cp.frec_b, coalesce(cp.activo, true) AS activo, cp.nota,
         coalesce(est.n_a, 0) AS n_a, coalesce(est.n_b, 0) AS n_b, coalesce(est.bajo_a, 0) AS bajo_a, coalesce(est.bajo_b, 0) AS bajo_b,
         ult.ult_a, ult.ult_b,
         coalesce(cp.dia_a, cfg.dia_a) AS dia_rev_a, coalesce(cp.frec_b, cfg.frec_b) AS frec_rev_b
  FROM todos t CROSS JOIN cfg
  LEFT JOIN compras_proveedores cp ON cp.base = cfg.base AND cp.proveedor_id = t.proveedor_id
  LEFT JOIN prv ON prv.proveedor_id = t.proveedor_id
  LEFT JOIN est ON est.proveedor_id = t.proveedor_id
  LEFT JOIN ult ON ult.proveedor_id = t.proveedor_id),
falta AS (  -- decisiones donde lo comprado es distinto a lo sugerido y no tienen razón
  SELECT count(*) AS n FROM compras_decisiones d JOIN compras_planes pl ON pl.id = d.plan_id, cfg
  WHERE pl.base = cfg.base AND coalesce(d.razon, '') = ''
    AND coalesce(d.oc_unidades, d.comprado, 0) IS DISTINCT FROM coalesce(d.sugerido, -1)),
sin_oc AS (SELECT count(*) AS n FROM compras_planes pl, cfg WHERE pl.base = cfg.base AND pl.docto_cm_id IS NULL
             AND pl.fecha < cfg.hoy - cfg.dias_ligar AND EXISTS (SELECT 1 FROM compras_decisiones d WHERE d.plan_id = pl.id AND d.comprado > 0)),
oc_sin_plan AS (SELECT count(*) AS n FROM oc, cfg WHERE oc.fecha >= cfg.hoy - 60
                  AND NOT EXISTS (SELECT 1 FROM compras_planes q WHERE q.base = cfg.base AND q.docto_cm_id = oc.id))
SELECT json_build_object(
  'ok', true, 'base', cfg.base, 'hoy', cfg.hoy::text, 'dow', extract(isodow FROM cfg.hoy)::int, 'cfg', cfg.c,
  'bases', (SELECT coalesce(json_agg(b ORDER BY n DESC), '[]'::json) FROM (SELECT base AS b, count(*) AS n FROM ms_ventas
             WHERE fecha >= current_date - 90 GROUP BY base) z),
  'mes', (SELECT mes FROM ms)::text,
  'meses', (SELECT coalesce(json_agg(x ORDER BY x.mes DESC), '[]'::json) FROM (
             SELECT mes::text AS mes, count(*) AS productos, count(*) FILTER (WHERE clase = 'A') AS a, count(*) FILTER (WHERE alerta IS NOT NULL) AS alertas,
                    max(calculado) AS calculado
             FROM compras_maxmin WHERE base = cfg.base GROUP BY mes ORDER BY mes DESC LIMIT 24) x),
  'proveedores', (SELECT coalesce(json_agg(pv ORDER BY (pv.n_a + pv.n_b) DESC, pv.nombre), '[]'::json) FROM pv),
  'sin_proveedor', (SELECT count(*) FROM mm WHERE proveedor_id IS NULL),
  'falta_razon', (SELECT n FROM falta), 'planes_sin_oc', (SELECT n FROM sin_oc), 'oc_sin_plan', (SELECT n FROM oc_sin_plan),
  'oc_detalle', EXISTS (SELECT 1 FROM ms_raw WHERE base = cfg.base AND tabla = 'DOCTOS_CM_DET' LIMIT 1),
  'oc_total', (SELECT count(*) FROM oc)) AS r
FROM cfg;
