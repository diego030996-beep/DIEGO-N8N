-- Agosto/septiembre: arma el registro a partir de las OCs que ya están en Microsip. p = {mes: 'YYYY-MM-01'}
-- Para cada renglón calcula la existencia que había el día de la OC, lo pendiente por recibir y el sugerido con los máx/mín de ese mes.
SET LOCAL statement_timeout = '180s';
SET LOCAL lock_timeout = '10s';
/*CALCULAR_SOLO_SI_FALTA*/
WITH /*CTX*/, /*OC*/,
m AS (SELECT date_trunc('month', coalesce(nullif(p->>'mes', '')::date, hoy))::date AS mes FROM cfg),
ids AS (SELECT o.id FROM oc o, m WHERE o.fecha >= m.mes AND o.fecha < (m.mes + interval '1 month')::date), /*OCD*/, /*EXCL*/
INSERT INTO compras_planes (base, fecha, proveedor_id, proveedor, clase, origen, docto_cm_id, folio, folio_oc, fecha_oc, ligado, por)
SELECT cfg.base, o.fecha, o.prov, coalesce(nullif(cp.nombre, ''), prv.nombre), 'OC', 'reconstruido', o.id, o.folio, o.folio, o.fecha, now(), cfg.por
FROM oc o CROSS JOIN cfg CROSS JOIN m
LEFT JOIN compras_proveedores cp ON cp.base = cfg.base AND cp.proveedor_id = o.prov
LEFT JOIN prv ON prv.proveedor_id = o.prov
WHERE o.fecha >= m.mes AND o.fecha < (m.mes + interval '1 month')::date
  AND NOT (EXISTS (SELECT 1 FROM ocd WHERE ocd.id = o.id)   -- OCs solo de artículos excluidos (tinacos) no entran
           AND NOT EXISTS (SELECT 1 FROM ocd WHERE ocd.id = o.id AND ocd.articulo_id NOT IN (SELECT articulo_id FROM excl)))
ON CONFLICT (base, docto_cm_id) WHERE docto_cm_id IS NOT NULL DO NOTHING;

WITH /*CTX*/, /*OC*/,
m AS (SELECT date_trunc('month', coalesce(nullif(p->>'mes', '')::date, hoy))::date AS mes FROM cfg),
pl AS (SELECT pl.id, pl.docto_cm_id, pl.fecha_oc AS f, pl.proveedor_id FROM compras_planes pl, cfg, m
       WHERE pl.base = cfg.base AND pl.origen = 'reconstruido' AND pl.fecha_oc >= m.mes AND pl.fecha_oc < (m.mes + interval '1 month')::date),
ids AS (SELECT o.id FROM oc o, m WHERE o.fecha >= m.mes - 60 AND o.fecha < (m.mes + interval '1 month')::date), /*OCD*/,
/*EXCL*/,
ln AS (SELECT pl.id AS plan_id, pl.f, pl.proveedor_id, d.articulo_id, d.u FROM pl JOIN ocd d ON d.id = pl.docto_cm_id
       WHERE d.articulo_id NOT IN (SELECT articulo_id FROM excl)),
arts AS (SELECT DISTINCT articulo_id FROM ln),
desde AS (SELECT coalesce(min(f), current_date) AS d FROM ln),
ahora AS (SELECT e.articulo_id, sum(coalesce(e.existencia, 0)) AS e FROM ms_existencias e, cfg
          WHERE e.base = cfg.base AND e.articulo_id IN (SELECT articulo_id FROM arts) AND (cfg.alm = '' OR coalesce(e.almacen, '') ~* cfg.alm) GROUP BY 1),
foto AS (  -- foto diaria del inventario (si el flujo de historial estaba prendido): existencia al cierre del día anterior
  SELECT h.fecha, h.articulo_id, sum(coalesce(h.existencia, 0)) AS e FROM ms_existencias_hist h, cfg, desde
  WHERE h.base = cfg.base AND h.articulo_id IN (SELECT articulo_id FROM arts) AND h.fecha >= desde.d - 1
    AND (cfg.alm = '' OR coalesce(h.almacen, '') ~* cfg.alm) GROUP BY 1, 2),
mov_r AS (  -- movimientos de inventario de Microsip con unidades (entradas +, salidas -)
  SELECT (r.datos->>'articulo_id')::bigint AS articulo_id, r.fecha,
         CASE WHEN upper(coalesce(r.datos->>'tipo', '')) = 'E' THEN 1 ELSE -1 END * abs(coalesce(r.datos->>'unidades', r.datos->>'UNIDADES')::numeric) AS u
  FROM ms_raw r, cfg, desde
  WHERE r.base = cfg.base AND r.tabla = 'RESUMEN_MOVTOS_IN' AND r.fecha >= desde.d AND (r.datos->>'articulo_id') ~ '^[0-9]{1,18}\Z'
    AND coalesce(r.datos->>'unidades', r.datos->>'UNIDADES') ~ '^-?[0-9]+(\.[0-9]+)?\Z'
    AND (CASE WHEN (r.datos->>'articulo_id') ~ '^[0-9]{1,18}\Z' THEN ((r.datos->>'articulo_id'))::bigint END) IN (SELECT articulo_id FROM arts)),
usar_r AS (SELECT EXISTS (SELECT 1 FROM ms_raw r, cfg, desde WHERE r.base = cfg.base AND r.tabla = 'RESUMEN_MOVTOS_IN' AND r.fecha >= desde.d
                          AND coalesce(r.datos->>'unidades', r.datos->>'UNIDADES') IS NOT NULL LIMIT 1) AS ok),
mov_v AS (  -- respaldo: ventas (salen) ...
  SELECT d.articulo_id, v.fecha, -(CASE WHEN upper(v.tipo) = 'D' THEN -1 ELSE 1 END) * abs(d.unidades) AS u
  FROM ms_ventas v JOIN ms_ventas_det d ON d.base = v.base AND d.origen = v.origen AND d.docto_id = v.docto_id, cfg, desde, usar_r
  WHERE NOT usar_r.ok AND v.base = cfg.base AND v.fecha >= desde.d AND coalesce(v.estatus, '') <> 'C'
    AND ((v.origen = 'PV' AND upper(v.tipo) IN ('V', 'D')) OR (v.origen = 'VE' AND v.tipo = 'R'))
    AND d.articulo_id IN (SELECT articulo_id FROM arts)),
cm AS (SELECT r.datos->>'DOCTO_CM_ID' AS id, upper(coalesce(r.datos->>'TIPO_DOCTO', '')) AS tipo, coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) AS fecha
       FROM ms_raw r, cfg, desde, usar_r
       WHERE NOT usar_r.ok AND r.base = cfg.base AND r.tabla = 'DOCTOS_CM' AND upper(coalesce(r.datos->>'TIPO_DOCTO', '')) IN ('R', 'C', 'D')
         AND upper(coalesce(r.datos->>'ESTATUS', '')) <> 'C' AND upper(coalesce(r.datos->>'CANCELADO', 'N')) <> 'S'
         AND coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) >= desde.d),
cm2 AS (SELECT cm.* FROM cm WHERE cm.tipo IN ('R', 'D') OR NOT EXISTS (   -- compras que salieron de una recepción ya se contaron
          SELECT 1 FROM lig JOIN cm r0 ON r0.id = lig.fte AND r0.tipo = 'R' WHERE lig.dst = cm.id)),
mov_c AS (  -- ... y compras (entran)
  SELECT (d.datos->>'ARTICULO_ID')::bigint AS articulo_id, cm2.fecha,
         CASE WHEN cm2.tipo = 'D' THEN -1 ELSE 1 END * CASE WHEN (d.datos->>'UNIDADES') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'UNIDADES')::numeric ELSE 0 END AS u
  FROM cm2 JOIN ms_raw d ON d.base = (SELECT base FROM cfg) AND d.tabla = 'DOCTOS_CM_DET' AND d.datos->>'DOCTO_CM_ID' = cm2.id
  WHERE (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z' AND (CASE WHEN (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z' THEN ((d.datos->>'ARTICULO_ID'))::bigint END) IN (SELECT articulo_id FROM arts)),
mov AS (SELECT * FROM mov_r WHERE (SELECT ok FROM usar_r) UNION ALL SELECT * FROM mov_v UNION ALL SELECT * FROM mov_c),
movd AS (SELECT articulo_id, fecha, sum(u) AS u FROM mov GROUP BY 1, 2),
desp AS (   -- lo que se movió desde el día de la OC hasta hoy, por renglón
  SELECT ln.plan_id, ln.articulo_id, sum(md.u) AS u FROM ln JOIN movd md ON md.articulo_id = ln.articulo_id AND md.fecha >= ln.f GROUP BY 1, 2),
pre AS (  -- pendiente: otras OCs del mismo artículo hechas en los días de entrega anteriores
  SELECT ln.plan_id, ln.articulo_id, sum(d.u) AS u
  FROM ln JOIN ocd d ON d.articulo_id = ln.articulo_id JOIN oc o ON o.id = d.id CROSS JOIN cfg
  LEFT JOIN compras_proveedores cp ON cp.base = cfg.base AND cp.proveedor_id = o.prov
  WHERE o.fecha < ln.f AND o.fecha >= ln.f - coalesce(cp.dias_entrega, cfg.ent_def)::int GROUP BY 1, 2),
x AS (
  SELECT ln.*, fo.e AS e_foto,
         coalesce(ah.e, 0) - coalesce(dp.u, 0) AS e_mov,
         coalesce(pre.u, 0) AS pendiente, mm.clave, mm.articulo, mm.unidad, mm.clase, mm.minimo, mm.maximo, coalesce(ov.empaque, mm.empaque) AS empaque,
         a.clave AS a_clave, a.nombre AS a_nombre, a.unidad AS a_unidad
  FROM ln CROSS JOIN cfg
  LEFT JOIN ahora ah ON ah.articulo_id = ln.articulo_id
  LEFT JOIN desp dp ON dp.plan_id = ln.plan_id AND dp.articulo_id = ln.articulo_id
  LEFT JOIN foto fo ON fo.articulo_id = ln.articulo_id AND fo.fecha = ln.f - 1
  LEFT JOIN pre ON pre.plan_id = ln.plan_id AND pre.articulo_id = ln.articulo_id
  LEFT JOIN compras_maxmin mm ON mm.base = cfg.base AND mm.mes = date_trunc('month', ln.f)::date AND mm.articulo_id = ln.articulo_id
  LEFT JOIN compras_articulos ov ON ov.base = cfg.base AND ov.articulo_id = ln.articulo_id
  LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = ln.articulo_id),
y AS (SELECT x.*, round(coalesce(x.e_foto, x.e_mov), 2) AS existencia,
             CASE WHEN x.e_foto IS NOT NULL THEN 'foto del inventario'
                  WHEN (SELECT ok FROM usar_r) THEN 'movimientos de inventario' ELSE 'ventas y compras (aprox.)' END AS metodo
      FROM x),
z AS (SELECT y.*, /*SUG(y.existencia, y.pendiente, y.minimo, y.maximo, y.empaque)*/ AS sugerido FROM y, cfg)
INSERT INTO compras_decisiones (plan_id, articulo_id, clave, articulo, unidad, clase, existencia, pendiente, minimo, maximo, sugerido, comprado,
  razon, oc_unidades, fuente, por)
SELECT z.plan_id, z.articulo_id, coalesce(z.clave, z.a_clave), coalesce(z.articulo, z.a_nombre), coalesce(z.unidad, z.a_unidad),
       coalesce(z.clase, 'sin venta'), z.existencia, z.pendiente, z.minimo, z.maximo, z.sugerido, z.u,
       CASE WHEN z.sugerido = z.u THEN 'igual' END, z.u, 'reconstruido: ' || z.metodo, cfg.por
FROM z, cfg
ON CONFLICT (plan_id, articulo_id) DO NOTHING;

WITH /*CTX*/,
m AS (SELECT date_trunc('month', coalesce(nullif(p->>'mes', '')::date, hoy))::date AS mes FROM cfg),
pl AS (SELECT pl.id FROM compras_planes pl, cfg, m WHERE pl.base = cfg.base AND coalesce(pl.fecha_oc, pl.fecha) >= m.mes
         AND coalesce(pl.fecha_oc, pl.fecha) < (m.mes + interval '1 month')::date),
d AS (SELECT d.* FROM compras_decisiones d JOIN pl ON pl.id = d.plan_id)
SELECT json_build_object('ok', true, 'mes', (SELECT mes FROM m)::text, 'ocs', (SELECT count(*) FROM pl),
  'renglones', (SELECT count(*) FROM d), 'iguales', (SELECT count(*) FROM d WHERE razon = 'igual'),
  'falta_razon', (SELECT count(*) FROM d WHERE coalesce(razon, '') = ''),
  'metodo', (SELECT string_agg(DISTINCT fuente, ', ') FROM d)) AS r;
