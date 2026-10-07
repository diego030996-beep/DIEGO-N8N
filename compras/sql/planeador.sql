-- Módulo 3: productos de un proveedor (o de todos) con existencia, por recibir, mínimo, punto de reorden, máximo y sugerido.
-- p = {proveedor_id} o {todos: 'si'} (en ese caso solo regresa lo que hay que pedir o ya se capturó hoy)
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*OC*/,
ms AS (SELECT max(mes) AS mes FROM compras_maxmin, cfg WHERE compras_maxmin.base = cfg.base AND mes <= cfg.hoy),
mm0 AS (SELECT x.articulo_id, x.clave, x.articulo, x.unidad, x.clase, x.venta_diaria, x.minimo, x.maximo, x.alerta, x.empaque,
               coalesce(x.punto_reorden, x.minimo) AS punto_reorden, x.rotacion, x.tickets, x.proveedor_id, x.proveedor,
               x.ultima_venta, x.semanas_venta, x.semanas, x.unidades, x.dias_periodo, x.presentaciones, x.dias_revision
        FROM compras_maxmin x, cfg, ms WHERE x.base = cfg.base AND x.mes = ms.mes
         AND (cfg.p->>'todos' = 'si' OR coalesce(x.proveedor_id, '') = coalesce(cfg.p->>'proveedor_id', ''))),
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
    WHERE d.tabla = 'DOCTOS_CM_DET' AND (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z' AND (SELECT count(*) FROM nv) > 0
      AND (CASE WHEN (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z' THEN ((d.datos->>'ARTICULO_ID'))::bigint END) IN (SELECT articulo_id FROM nv)
      AND upper(coalesce(r.datos->>'TIPO_DOCTO', '')) IN ('O', 'R', 'C') AND upper(coalesce(r.datos->>'ESTATUS', '')) <> 'C') z
  ORDER BY z.articulo_id, z.fecha DESC),
nv2 AS (
  SELECT nv.articulo_id, a.clave, a.nombre AS articulo, a.unidad, nv.u / greatest(cfg.hoy - ms.mes + 1, 1) AS vd,
         coalesce(cp.dias_entrega, cfg.ent_def) AS ent, ov.minimo AS min_f, ov.maximo AS max_f, ov.empaque,
         coalesce(nullif(ov.proveedor_id, ''), nvc.prov) AS prov, cp.nombre AS prov_nom
  FROM nv CROSS JOIN cfg CROSS JOIN ms
  LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = nv.articulo_id
  LEFT JOIN compras_articulos ov ON ov.base = cfg.base AND ov.articulo_id = nv.articulo_id
  LEFT JOIN nvc ON nvc.articulo_id = nv.articulo_id
  LEFT JOIN compras_proveedores cp ON cp.base = cfg.base AND cp.proveedor_id = coalesce(nullif(ov.proveedor_id, ''), nvc.prov)
  WHERE cfg.p->>'todos' = 'si' OR coalesce(nullif(ov.proveedor_id, ''), nvc.prov, '') = coalesce(cfg.p->>'proveedor_id', '')),
nv3 AS (SELECT nv2.*, greatest(coalesce(nv2.min_f, ceil(nv2.vd * (nv2.ent + cfg.seg_c))), cfg.min_c) AS mn FROM nv2, cfg),
mm AS (SELECT * FROM mm0
       UNION ALL
       SELECT nv3.articulo_id, nv3.clave, nv3.articulo, nv3.unidad, 'C', round(nv3.vd, 4), nv3.mn,
              greatest(coalesce(nv3.max_f, nv3.mn + ceil(nv3.vd * cfg.inv_c)), nv3.mn + 1),
              'nuevo: se vendió este mes y aún no tiene clase (entra como C hasta el próximo cálculo)', nv3.empaque,
              nv3.mn, 'nuevo', NULL::int, nv3.prov, nv3.prov_nom, NULL::date, NULL::int, NULL::int, NULL::numeric, NULL::int, NULL::text, NULL::numeric
       FROM nv3, cfg),
ids AS (SELECT id FROM oc, cfg WHERE oc.fecha >= cfg.hoy - 120), /*OCD*/, /*LT*/, /*EXI*/,
pl AS (SELECT pl.* FROM compras_planes pl, cfg WHERE pl.base = cfg.base AND pl.fecha = cfg.hoy AND pl.origen = 'planeador'
         AND (cfg.p->>'todos' = 'si' OR pl.proveedor_id = cfg.p->>'proveedor_id')),
dec AS (SELECT d.*, pl.proveedor_id AS dprov FROM compras_decisiones d JOIN pl ON pl.id = d.plan_id),
uc AS (  -- última OC del artículo con este proveedor
  SELECT DISTINCT ON (d.articulo_id) d.articulo_id, o.fecha, d.u FROM oc o JOIN ocd d ON d.id = o.id, cfg
  WHERE cfg.p->>'todos' = 'si' OR o.prov = cfg.p->>'proveedor_id' ORDER BY d.articulo_id, o.fecha DESC),
vm AS (  -- última venta al día de hoy (las de este mes todavía no están en el cálculo)
  SELECT d.articulo_id, max(v.fecha) AS fecha
  FROM ms_ventas v JOIN ms_ventas_det d ON d.base = v.base AND d.origen = v.origen AND d.docto_id = v.docto_id, cfg, ms
  WHERE v.base = cfg.base AND v.fecha >= ms.mes AND coalesce(v.estatus, '') <> 'C' AND upper(v.tipo) <> 'D'
    AND ((v.origen = 'PV' AND upper(v.tipo) = 'V') OR (v.origen = 'VE' AND v.tipo = 'R')) AND d.articulo_id IS NOT NULL
  GROUP BY 1),
rc AS MATERIALIZED (  -- recepciones y compras de Microsip (lo que de verdad entró al almacén) de los últimos 2 años
  SELECT r.datos->>'DOCTO_CM_ID' AS id, coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) AS fecha, r.datos->>'PROVEEDOR_ID' AS prov
  FROM ms_raw r, cfg
  WHERE r.base = cfg.base AND r.tabla = 'DOCTOS_CM' AND upper(coalesce(r.datos->>'TIPO_DOCTO', '')) IN ('R', 'C')
    AND upper(coalesce(r.datos->>'ESTATUS', '')) <> 'C' AND upper(coalesce(r.datos->>'CANCELADO', 'N')) <> 'S'
    AND coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) >= cfg.hoy - 730),
rcd AS MATERIALIZED (  -- renglones de compras de los artículos del planeador (se leen una sola vez)
  SELECT z.* FROM (
    SELECT d.datos->>'DOCTO_CM_ID' AS id,
           (CASE WHEN (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z' THEN (d.datos->>'ARTICULO_ID')::bigint END) AS articulo_id,
           CASE WHEN (d.datos->>'UNIDADES') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'UNIDADES')::numeric END AS u,
           CASE WHEN (d.datos->>'PRECIO_UNITARIO') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'PRECIO_UNITARIO')::numeric END AS precio
    FROM ms_raw d, cfg WHERE d.base = cfg.base AND d.tabla = 'DOCTOS_CM_DET') z
  WHERE z.articulo_id IN (SELECT articulo_id FROM mm)),
ur AS (  -- última recepción de cada artículo del planeador
  SELECT DISTINCT ON (rcd.articulo_id) rcd.articulo_id, rc.fecha, rcd.u, rc.prov, rcd.precio
  FROM rcd JOIN rc ON rc.id = rcd.id
  ORDER BY rcd.articulo_id, rc.fecha DESC),
plsin AS (  -- planes guardados en días anteriores que todavía no son orden de compra en Microsip
  SELECT d.articulo_id, sum(d.comprado) AS u, string_agg(DISTINCT to_char(pl.fecha, 'DD/MM'), ', ') AS fechas
  FROM compras_planes pl JOIN compras_decisiones d ON d.plan_id = pl.id, cfg
  WHERE pl.base = cfg.base AND pl.origen = 'planeador' AND pl.docto_cm_id IS NULL AND pl.fecha >= cfg.hoy - 14 AND pl.fecha < cfg.hoy
    AND d.comprado > 0 GROUP BY 1),
polv AS (SELECT p.articulo_id, p.politica, p.minimo FROM compras_politica p, cfg WHERE p.base = cfg.base),
f AS (
  SELECT mm.articulo_id, mm.clave, mm.articulo, mm.unidad, mm.clase, mm.venta_diaria, mm.minimo, mm.maximo, mm.alerta,
         mm.punto_reorden, mm.rotacion, mm.tickets, mm.proveedor_id, mm.proveedor, mm.ultima_venta, mm.semanas_venta, mm.semanas, mm.unidades, mm.dias_periodo,
         (SELECT r.decision FROM compras_revision r WHERE r.base = cfg.base AND r.articulo_id = mm.articulo_id AND r.tipo = 'lento') AS lento,
         coalesce(ov.empaque, mm.empaque) AS empaque, coalesce(exi.e, 0) AS existencia, coalesce(pend.u, 0) AS pendiente, pend.folios,
         uc.fecha AS ult_fecha, uc.u AS ult_unidades, ur.fecha AS rec_fecha, ur.u AS rec_unidades, ur.prov AS rec_prov,
         greatest(vm.fecha, mm.ultima_venta) AS ult_venta,
         exi.por_almacen, coalesce(exi.algun_negativo, false) AS algun_negativo, pend.atr_u, pend.atr_folios,
         ltp.dias AS lt_conocido, coalesce(ltp.dias, cfg.ent_def) AS lt, ltp.medido AS lt_medido, ltp.n AS lt_n,
         coalesce(mm.dias_revision, CASE WHEN mm.clase = 'A' THEN cfg.rev_a ELSE cfg.frec_b END) AS rev,
         polv.politica, polv.minimo AS pol_min, mm.presentaciones,
         coalesce(nullif(a.costo_ultimo, 0), ur.precio) AS costo,
         CASE WHEN nullif(a.costo_ultimo, 0) IS NOT NULL THEN 'último costo' WHEN ur.precio IS NOT NULL THEN 'última compra' END AS costo_fuente,
         plsin.u AS plan_sin_oc, plsin.fechas AS plan_sin_oc_fechas,
         CASE WHEN (mm.articulo ~* 'TONELADA' AND coalesce(mm.unidad, '') !~* 'TON')
                THEN 'El nombre dice TONELADA pero la unidad en Microsip es ' || coalesce(mm.unidad, '(vacía)')
              WHEN (mm.articulo ~* 'MILLAR' AND coalesce(mm.unidad, '') !~* 'MILL')
                THEN 'El nombre dice MILLAR pero la unidad en Microsip es ' || coalesce(mm.unidad, '(vacía)')
              WHEN (mm.articulo ~* '(ARENA|GRAVA|TEZONTLE|TEPETATE|GRANZON)' AND mm.articulo !~* '(S/ *ARENA|SIN ARENA|COSTAL|BULTO)'
                    AND coalesce(mm.unidad, '') ~* 'CUADRAD')
                THEN 'Material a granel con unidad ' || mm.unidad || ' (¿debería ser metro cúbico?)' END AS unidad_aviso
  FROM mm CROSS JOIN cfg
  LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = mm.articulo_id
  LEFT JOIN ltp ON ltp.prov = mm.proveedor_id
  LEFT JOIN plsin ON plsin.articulo_id = mm.articulo_id
  LEFT JOIN polv ON polv.articulo_id = mm.articulo_id
  LEFT JOIN compras_articulos ov ON ov.base = cfg.base AND ov.articulo_id = mm.articulo_id
  LEFT JOIN exi ON exi.articulo_id = mm.articulo_id LEFT JOIN pend ON pend.articulo_id = mm.articulo_id
  LEFT JOIN uc ON uc.articulo_id = mm.articulo_id LEFT JOIN ur ON ur.articulo_id = mm.articulo_id
  LEFT JOIN vm ON vm.articulo_id = mm.articulo_id),
g0 AS (SELECT f.*, CASE WHEN f.politica = 'bajo_pedido' THEN 0 ELSE /*SUG(f.existencia, f.pendiente, f.punto_reorden, f.maximo, f.empaque)*/ END AS sugerido,
              greatest(f.existencia, 0) + f.pendiente AS pos FROM f, cfg),
g AS (
  SELECT g0.*,
         CASE WHEN g0.politica = 'bajo_pedido' THEN 'bajo_pedido'
              WHEN g0.venta_diaria > 0 AND g0.pos < g0.venta_diaria * g0.lt THEN 'critico'   -- se agota antes de que llegue un pedido
              WHEN g0.pos <= g0.punto_reorden THEN 'pedir'
              WHEN g0.pos <= g0.punto_reorden + g0.venta_diaria * g0.rev THEN 'proximo'       -- llega al punto de reorden antes de la siguiente revisión
              ELSE 'bien' END AS estado,
         array_remove(ARRAY[
           CASE WHEN g0.existencia < 0 OR g0.algun_negativo THEN 'Existencia negativa (' || coalesce(g0.por_almacen, '') || '): el sugerido se calcula como si fuera 0. Corrige el inventario en Microsip.' END,
           g0.unidad_aviso,
           CASE WHEN g0.proveedor_id IS NULL THEN 'Sin proveedor: asígnalo para poder pedirlo.'
                WHEN g0.lt_conocido IS NULL THEN 'Días de entrega desconocidos: se usaron ' || g0.lt || '. Escríbelos o espera a que se midan con las recepciones.' END,
           CASE WHEN coalesce(g0.atr_u, 0) > 0 THEN 'OC atrasada sin recibir: ' || g0.atr_folios || ' (' || trim(to_char(g0.atr_u, 'FM999999990.##')) || ') no se cuenta como por recibir; confírmala en Seguimiento.' END,
           CASE WHEN coalesce(g0.plan_sin_oc, 0) > 0 THEN 'Ya hay ' || trim(to_char(g0.plan_sin_oc, 'FM999999990.##')) || ' en un plan guardado el ' || g0.plan_sin_oc_fechas || ' que todavía no es OC en Microsip.' END,
           CASE WHEN g0.politica IS NULL AND g0.lento IS DISTINCT FROM 'queda' AND (g0.rotacion = 'baja' OR (g0.clase = 'C' AND g0.rotacion IS DISTINCT FROM 'alta'))
                THEN 'Vende poco: elige si se mantiene un mínimo, solo bajo pedido o se pausa.' END
         ], NULL) AS revisar
  FROM g0)
SELECT json_build_object('ok', true, 'mes', (SELECT mes FROM ms)::text, 'proveedor_id', cfg.p->>'proveedor_id', 'regla', cfg.regla,
  'plan', (SELECT json_build_object('id', id, 'folio', folio, 'folio_oc', folio_oc, 'clase', clase, 'creado', creado, 'modificado', modificado)
           FROM pl WHERE cfg.p->>'todos' IS DISTINCT FROM 'si' LIMIT 1),
  'filas', (SELECT coalesce(json_agg(json_build_object(
      'articulo_id', g.articulo_id, 'clave', g.clave, 'articulo', g.articulo, 'unidad', g.unidad, 'clase', g.clase,
      'vd', round(g.venta_diaria, 2), 'minimo', g.minimo, 'maximo', g.maximo, 'punto_reorden', g.punto_reorden, 'rotacion', g.rotacion,
      'tickets', g.tickets, 'proveedor_id', g.proveedor_id, 'proveedor', g.proveedor, 'ultima_venta', g.ultima_venta,
      'semanas_venta', g.semanas_venta, 'semanas', g.semanas, 'lento', g.lento, 'unidades', g.unidades, 'dias_periodo', g.dias_periodo, 'empaque', g.empaque, 'alerta', g.alerta,
      'existencia', g.existencia, 'pendiente', g.pendiente, 'folios', g.folios, 'sugerido', g.sugerido,
      'ult_fecha', g.ult_fecha, 'ult_unidades', g.ult_unidades, 'rec_fecha', g.rec_fecha, 'rec_unidades', g.rec_unidades, 'rec_prov', g.rec_prov,
      'rec_proveedor', (SELECT p.datos->>'NOMBRE' FROM ms_raw p WHERE p.base = cfg.base AND p.tabla = 'PROVEEDORES' AND p.pk = g.rec_prov),
      'ult_venta', g.ult_venta,
      'comprado', dec.comprado, 'razon', dec.razon, 'nota', dec.nota,
      'estado', g.estado, 'revisar', g.revisar, 'costo', g.costo, 'costo_fuente', g.costo_fuente, 'lt', g.lt, 'lt_medido', g.lt_medido,
      'lt_n', g.lt_n, 'rev', g.rev, 'politica', g.politica, 'pol_min', g.pol_min, 'presentaciones', g.presentaciones, 'por_almacen', g.por_almacen,
      'atr_u', g.atr_u, 'atr_folios', g.atr_folios, 'plan_sin_oc', g.plan_sin_oc)
      ORDER BY g.proveedor, g.clase, (g.sugerido > 0) DESC, (greatest(g.existencia, 0) + g.pendiente) / nullif(g.punto_reorden, 0), g.articulo), '[]'::json)
    FROM g LEFT JOIN dec ON dec.articulo_id = g.articulo_id AND coalesce(dec.dprov, '') = coalesce(g.proveedor_id, '')
    WHERE NOT EXISTS (SELECT 1 FROM excl WHERE excl.articulo_id = g.articulo_id)   -- lo que se marcó para ya no comprar sale de inmediato
      AND (cfg.p->>'todos' IS DISTINCT FROM 'si' OR g.sugerido > 0 OR dec.articulo_id IS NOT NULL
       OR g.estado IN ('critico', 'pedir') OR coalesce(g.atr_u, 0) > 0 OR g.existencia < 0)),
  'resumen', (SELECT json_build_object(   -- conteos y costos de TODO (no solo de lo que se muestra)
      'estados', (SELECT json_object_agg(estado, n) FROM (SELECT estado, count(*) AS n FROM g
                    WHERE NOT EXISTS (SELECT 1 FROM excl WHERE excl.articulo_id = g.articulo_id) GROUP BY 1) z),
      'revisar', (SELECT count(*) FROM g WHERE cardinality(revisar) > 0 AND NOT EXISTS (SELECT 1 FROM excl WHERE excl.articulo_id = g.articulo_id)),
      'proveedores', (SELECT coalesce(json_agg(z ORDER BY z.costo DESC NULLS LAST), '[]'::json) FROM (
          SELECT coalesce(g.proveedor_id, '') AS proveedor_id, max(g.proveedor) AS proveedor,
                 count(*) FILTER (WHERE estado = 'critico') AS critico, count(*) FILTER (WHERE estado = 'pedir') AS pedir,
                 count(*) FILTER (WHERE estado = 'proximo') AS proximo, count(*) FILTER (WHERE estado = 'bien') AS bien,
                 count(*) FILTER (WHERE cardinality(revisar) > 0) AS revisar,
                 round(sum(g.sugerido * coalesce(g.costo, 0)), 2) AS costo, count(*) FILTER (WHERE g.sugerido > 0 AND g.costo IS NULL) AS sin_costo
          FROM g WHERE NOT EXISTS (SELECT 1 FROM excl WHERE excl.articulo_id = g.articulo_id) GROUP BY 1) z),
      'iva', cfg.iva))) AS r
FROM cfg;
