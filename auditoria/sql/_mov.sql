ret0 AS (   -- retiros de caja (punto de venta, tipo R) desde que empezó la auditoría, sin cancelados
  SELECT v.docto_id::text AS id, v.folio, v.fecha, left(coalesce(v.hora, ''), 5) AS hora, trim(coalesce(v.descripcion, '')) AS descripcion,
         coalesce(v.usuario, '') AS usuario, abs(coalesce(v.total, 0)) AS total
  FROM ms_ventas_v v, cfg
  WHERE v.base = cfg.base AND v.origen = 'PV' AND upper(v.tipo) = 'R' AND NOT v.cancelado AND v.fecha >= cfg.desde
    AND (cfg.excl = '' OR NOT (coalesce(v.descripcion, '') ~* cfg.excl))),
rcob AS (   -- importe del retiro según sus cobros (efectivo que salió)
  SELECT c.datos->>'DOCTO_PV_ID' AS id, abs(sum(CASE WHEN jsonb_typeof(c.datos->'IMPORTE') = 'number' THEN (c.datos->>'IMPORTE')::numeric ELSE 0 END)) AS importe
  FROM ms_raw c, cfg WHERE c.base = cfg.base AND c.tabla = 'DOCTOS_PV_COBROS' AND c.datos->>'DOCTO_PV_ID' IN (SELECT id FROM ret0) GROUP BY 1),
ret AS (SELECT r.*, coalesce(nullif(rc.importe, 0), r.total) AS importe FROM ret0 r LEFT JOIN rcob rc ON rc.id = r.id),
cob0 AS (   -- cobros de caja con formas que piden comprobante (tarjeta → voucher, transferencia, Mercado Pago), por ticket y forma
  SELECT v.docto_id::text AS docto, v.folio, v.fecha, left(coalesce(v.hora, ''), 5) AS hora, coalesce(v.usuario, '') AS usuario, coalesce(v.cliente, '') AS cliente,
         c.datos->>'FORMA_COBRO_ID' AS forma_id, coalesce(fc.datos->>'NOMBRE', 'Forma ' || (c.datos->>'FORMA_COBRO_ID')) AS forma,
         sum(CASE WHEN upper(coalesce(c.datos->>'TIPO', 'C')) = 'A' THEN -1 ELSE 1 END
             * CASE WHEN jsonb_typeof(c.datos->'IMPORTE') = 'number' THEN (c.datos->>'IMPORTE')::numeric ELSE 0 END) AS importe,
         max(nullif(trim(coalesce(c.datos->>'REFERENCIA', c.datos->>'NUM_AUTORIZACION', '')), '')) AS referencia
  FROM ms_ventas_v v CROSS JOIN cfg
  JOIN ms_raw c ON c.base = v.base AND c.tabla = 'DOCTOS_PV_COBROS' AND c.datos->>'DOCTO_PV_ID' = v.docto_id::text
  JOIN ms_raw fc ON fc.base = v.base AND fc.tabla = 'FORMAS_COBRO' AND fc.pk = c.datos->>'FORMA_COBRO_ID'
  WHERE v.base = cfg.base AND v.origen = 'PV' AND upper(v.tipo) IN ('V', 'P') AND NOT v.cancelado AND v.fecha >= cfg.desde
    AND cfg.formas <> '' AND coalesce(fc.datos->>'NOMBRE', '') ~* cfg.formas
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8),
cob AS (
  SELECT c.*, c.docto || ':' || c.forma_id AS id,
         CASE WHEN c.forma ~* 'tarjeta|t\.? ?d\.? ?[cd]|terminal|d[eé]bito|cr[eé]dito' THEN 'voucher' WHEN c.forma ~* 'mercado' THEN 'Mercado Pago' ELSE 'transferencia' END AS que,
         (CASE WHEN c.hora ~ '^[0-9]{1,2}:[0-9]{2}' AND c.hora::time > cfg.cierre THEN c.fecha + 1 ELSE c.fecha END) + cfg.cierre AS vence
  FROM cob0 c, cfg WHERE c.importe > 0),
cm0 AS (   -- compras (C) y recepciones (R) de Microsip, sin canceladas
  SELECT r.datos->>'DOCTO_CM_ID' AS id, upper(r.datos->>'TIPO_DOCTO') AS tipo, coalesce(r.datos->>'FOLIO', '') AS folio,
         coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) AS fecha, r.datos->>'PROVEEDOR_ID' AS prov, r.datos->>'COND_PAGO_ID' AS cond,
         (CASE WHEN (r.datos->>'IMPORTE_NETO') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (r.datos->>'IMPORTE_NETO')::numeric ELSE 0 END
          + CASE WHEN (r.datos->>'TOTAL_IMPUESTOS') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (r.datos->>'TOTAL_IMPUESTOS')::numeric ELSE 0 END) AS total
  FROM ms_raw r, cfg
  WHERE r.base = cfg.base AND r.tabla = 'DOCTOS_CM' AND upper(coalesce(r.datos->>'TIPO_DOCTO', '')) IN ('R', 'C')
    AND upper(coalesce(r.datos->>'ESTATUS', '')) <> 'C' AND upper(coalesce(r.datos->>'CANCELADO', 'N')) NOT IN ('S', 'SI', 'Y', 'T', '1', 'TRUE')
    AND coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) >= cfg.desde - 10),
cml AS (   -- recepciones que ya pasaron a compra: cuenta solo la compra (no se duplica)
  SELECT DISTINCT coalesce(r.datos->>'DOCTO_CM_FTE_ID', r.datos->>'DOCTO_CM_ID_FTE', r.datos->>'DOCTO_FTE_ID') AS fte
  FROM ms_raw r, cfg WHERE r.base = cfg.base AND r.tabla = 'DOCTOS_CM_LIGAS'
    AND coalesce(r.datos->>'DOCTO_CM_DEST_ID', r.datos->>'DOCTO_CM_ID_DEST', r.datos->>'DOCTO_DEST_ID') IN (SELECT id FROM cm0 WHERE tipo = 'C')),
cmp AS (
  SELECT c.*, coalesce(p.datos->>'NOMBRE', '') AS proveedor, coalesce(cp.datos->>'NOMBRE', '') AS cond_nombre
  FROM cm0 c CROSS JOIN cfg
  LEFT JOIN ms_raw p ON p.base = cfg.base AND p.tabla = 'PROVEEDORES' AND p.pk = c.prov
  LEFT JOIN ms_raw cp ON cp.base = cfg.base AND cp.tabla = 'CONDICIONES_PAGO' AND cp.pk = c.cond
  WHERE NOT (c.tipo = 'R' AND c.id IN (SELECT fte FROM cml WHERE fte IS NOT NULL))),
ign AS (SELECT i.tipo, i.ref, i.motivo, i.por, i.creado FROM mov_ignorado i, cfg WHERE i.base = cfg.base),
cbr AS (   -- cobros con tarjeta / transferencia / Mercado Pago sin comprobante subido
  SELECT c.* FROM cob c WHERE c.id NOT IN (SELECT cobro_id FROM mov_registro g, cfg WHERE g.base = cfg.base AND NOT g.borrado AND g.cobro_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM ign WHERE ign.tipo = 'cobro' AND ign.ref = c.id)),
reg0 AS (
  SELECT g.*, coalesce(k.n, 0) AS fotos, coalesce(k.comprobado, 0) AS comprobado, (g.tipo = ANY (cfg.tipos_compra)) AS req_compra,
         upper(regexp_replace(coalesce(g.pedido, ''), '[^A-Za-z]', '', 'g')) || coalesce(nullif(ltrim(regexp_replace(coalesce(g.pedido, ''), '[^0-9]', '', 'g'), '0'), ''), '') AS ped_norm
  FROM mov_registro g CROSS JOIN cfg
  LEFT JOIN (SELECT registro_id, count(*) AS n, sum(importe) AS comprobado FROM mov_comprobante GROUP BY 1) k ON k.registro_id = g.id
  WHERE g.base = cfg.base AND NOT g.borrado),
par AS (   -- compras de Microsip que podrían ser de cada registro (mismo importe ± tolerancia, fechas cercanas)
  -- d1 = contra lo comprobado (preferido), d2 = contra lo retirado
  SELECT g.id AS reg_id, c.id AS cm_id, abs(c.total - coalesce(nullif(g.comprobado, 0), g.importe)) AS d1, abs(c.total - g.importe) AS d2,
         abs(c.fecha - g.fecha) AS dd, g.fecha AS gf, greatest(cfg.tol, g.importe * 0.01) AS t
  FROM reg0 g CROSS JOIN cfg JOIN cmp c ON c.fecha BETWEEN g.fecha - 2 AND g.fecha + cfg.dias_compra
  WHERE g.req_compra AND g.compra_id IS NULL AND g.revision IS DISTINCT FROM 'aprobado'
    AND c.id NOT IN (SELECT compra_id FROM reg0 WHERE compra_id IS NOT NULL)
    AND least(abs(c.total - coalesce(nullif(g.comprobado, 0), g.importe)), abs(c.total - g.importe)) <= greatest(cfg.tol, g.importe * cfg.margen)),
par1 AS (SELECT p.*, row_number() OVER (PARTITION BY reg_id ORDER BY d1, d2, dd, cm_id) AS rn, min(d1) OVER (PARTITION BY reg_id) AS m1 FROM par p),
par1b AS (SELECT p.*, count(*) FILTER (WHERE d1 <= m1 + 0.005) OVER (PARTITION BY reg_id) AS cands FROM par1 p),
r1 AS (SELECT reg_id, cm_id, cands FROM (SELECT p.*, row_number() OVER (PARTITION BY cm_id ORDER BY d1, gf, reg_id) AS rc FROM par1b p WHERE rn = 1) z WHERE rc = 1),
par2 AS (   -- segunda vuelta para los que perdieron su compra contra otro registro
  SELECT p.*, row_number() OVER (PARTITION BY reg_id ORDER BY d1, d2, dd, cm_id) AS rn2 FROM par1b p
  WHERE p.reg_id NOT IN (SELECT reg_id FROM r1) AND p.cm_id NOT IN (SELECT cm_id FROM r1)),
r2 AS (SELECT reg_id, cm_id, cands FROM (SELECT p.*, row_number() OVER (PARTITION BY cm_id ORDER BY d1, gf, reg_id) AS rc FROM par2 p WHERE rn2 = 1) z WHERE rc = 1),
auto AS (SELECT * FROM r1 UNION ALL SELECT * FROM r2),
ped AS (   -- pedidos / remisiones / facturas de Ventas que se mencionan
  SELECT DISTINCT ON (fn) v.folio, v.tipo, v.fecha, v.cliente, v.total, v.cancelado, x.fn
  FROM ms_ventas_v v CROSS JOIN cfg
  CROSS JOIN LATERAL (SELECT upper(regexp_replace(v.folio, '[^A-Za-z]', '', 'g')) || coalesce(nullif(ltrim(regexp_replace(v.folio, '[^0-9]', '', 'g'), '0'), ''), '') AS fn) x
  WHERE v.base = cfg.base AND v.origen = 'VE' AND v.tipo IN ('P', 'R', 'F') AND x.fn IN (SELECT ped_norm FROM reg0 WHERE ped_norm <> '')
  ORDER BY fn, v.cancelado, (v.tipo = 'P') DESC, v.fecha DESC),
reg AS (
  SELECT g.*, coalesce(g.compra_id, a.cm_id) AS cm_id, (g.compra_id IS NULL AND a.cm_id IS NOT NULL) AS cm_auto, coalesce(a.cands, 0) AS cands,
         c.folio AS cm_folio, c.total AS cm_total, c.proveedor AS cm_proveedor, c.fecha AS cm_fecha,
         pd.folio AS ped_folio, pd.cliente AS ped_cliente, pd.cancelado AS ped_cancelado, pd.tipo AS ped_tipo,
         r.folio AS ret_folio_ms, r.importe AS ret_importe,
         (CASE WHEN coalesce(g.hora, '') ~ '^[0-9]{1,2}:[0-9]{2}' AND left(g.hora, 5)::time > cfg.cierre THEN g.fecha + 1 ELSE g.fecha END) + cfg.cierre AS vence,
         g.importe - g.comprobado AS falta
  FROM reg0 g CROSS JOIN cfg
  LEFT JOIN auto a ON a.reg_id = g.id
  LEFT JOIN cmp c ON c.id = coalesce(g.compra_id, a.cm_id)
  LEFT JOIN ped pd ON pd.fn = g.ped_norm AND g.ped_norm <> ''
  LEFT JOIN ret r ON r.id = g.retiro_id),
est AS (   -- semáforo de cada registro (la primera regla que aplica)
  SELECT g.*, cfg.ahora > g.vence AS vencido,
    CASE WHEN g.revision = 'aprobado' THEN 'verde' WHEN g.revision = 'inconsistencia' THEN 'rojo'
         WHEN g.fotos = 0 THEN CASE WHEN cfg.ahora > g.vence THEN 'rojo' ELSE 'pendiente' END
         WHEN g.req_compra AND g.cm_id IS NULL THEN CASE WHEN cfg.ahora > g.vence THEN 'rojo' ELSE 'pendiente' END
         WHEN abs(g.falta) > cfg.tol THEN 'naranja'
         WHEN g.req_compra AND abs(g.cm_total - g.comprobado) > greatest(cfg.tol, g.comprobado * 0.01) THEN 'naranja'
         WHEN g.ped_norm <> '' AND (g.ped_folio IS NULL OR g.ped_cancelado) THEN 'naranja'
         WHEN g.cands > 1 THEN 'naranja'
         ELSE 'verde' END AS estado,
    CASE WHEN g.revision = 'aprobado' THEN 'Aprobado por ' || coalesce(g.revisado_por, 'auditoría')
         WHEN g.revision = 'inconsistencia' THEN 'INCONSISTENCIA' || coalesce(': ' || nullif(g.revision_nota, ''), '')
         WHEN g.fotos = 0 THEN CASE WHEN cfg.ahora > g.vence THEN 'FALTA COMPROBANTE' ELSE 'Falta subir comprobante' END
         WHEN g.req_compra AND g.cm_id IS NULL THEN CASE WHEN cfg.ahora > g.vence THEN 'COMPRA NO REGISTRADA en Microsip' ELSE 'Falta registrar la compra en Microsip' END
         WHEN g.falta > cfg.tol THEN 'Faltan comprobar ' || to_char(g.falta, 'FM999,999,990.00')
         WHEN g.falta < -cfg.tol THEN 'Comprobado de más ' || to_char(-g.falta, 'FM999,999,990.00')
         WHEN g.req_compra AND abs(g.cm_total - g.comprobado) > greatest(cfg.tol, g.comprobado * 0.01)
           THEN 'La compra en Microsip es de ' || to_char(g.cm_total, 'FM999,999,990.00') || ' y lo comprobado ' || to_char(g.comprobado, 'FM999,999,990.00')
         WHEN g.ped_norm <> '' AND g.ped_folio IS NULL THEN 'REVISAR PEDIDO: ' || g.pedido || ' no existe en Microsip'
         WHEN g.ped_norm <> '' AND g.ped_cancelado THEN 'REVISAR PEDIDO: ' || g.ped_folio || ' está cancelado'
         WHEN g.cands > 1 THEN 'Revisar compra: hay ' || g.cands || ' compras posibles con ese importe'
         ELSE 'Cuadrado' END AS motivo
  FROM reg g, cfg),
rsr AS (   -- retiros de caja que nadie ha reportado
  SELECT r.*, (CASE WHEN r.hora ~ '^[0-9]{1,2}:[0-9]{2}' AND r.hora::time > cfg.cierre THEN r.fecha + 1 ELSE r.fecha END) + cfg.cierre AS vence
  FROM ret r, cfg
  WHERE NOT EXISTS (SELECT 1 FROM reg0 g WHERE g.retiro_id = r.id) AND NOT EXISTS (SELECT 1 FROM ign WHERE ign.tipo = 'retiro' AND ign.ref = r.id)),
csr AS (   -- compras de contado / de mostrador en Microsip sin comprobante (cuando se configura)
  SELECT c.*, (c.fecha + 1) + cfg.cierre AS vence
  FROM cmp c, cfg
  WHERE c.fecha >= cfg.desde AND cfg.csc <> 'no'
    AND (cfg.csc = 'todas' OR (cfg.prov_most <> '' AND c.proveedor ~* cfg.prov_most) OR (cfg.csc = 'contado' AND c.cond_nombre ~* 'contado'))
    AND c.id NOT IN (SELECT cm_id FROM reg WHERE cm_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM ign WHERE ign.tipo = 'compra' AND ign.ref = c.id)),
mov AS (   -- todo junto, con el mismo formato
  SELECT 'registro' AS clase, e.id::text AS ref, e.fecha, coalesce(left(e.hora, 5), to_char(e.creado AT TIME ZONE 'America/Mexico_City', 'HH24:MI')) AS hora,
         coalesce(nullif(e.retiro_folio, ''), 'M-' || e.id) AS folio, e.empleado, e.concepto, e.tipo, e.metodo, e.importe, e.comprobado, e.falta,
         e.estado, e.motivo, e.vence, e.fotos, e.pedido, e.cm_folio, e.cm_total, e.cm_proveedor, e.cm_auto, e.revision, e.id AS registro_id
  FROM est e
  UNION ALL
  SELECT 'retiro', r.id, r.fecha, r.hora, r.folio, r.usuario, coalesce(nullif(r.descripcion, ''), 'Retiro de caja'), 'retiro', 'efectivo', r.importe, 0, r.importe,
         CASE WHEN cfg.ahora > r.vence THEN 'rojo' ELSE 'pendiente' END,
         CASE WHEN cfg.ahora > r.vence THEN 'RETIRO SIN COMPROBAR' ELSE 'Retiro sin reportar' END, r.vence, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM rsr r, cfg
  UNION ALL
  SELECT 'compra', c.id, c.fecha, NULL, c.folio, c.proveedor, 'Compra en Microsip ' || c.folio || coalesce(' · ' || nullif(c.proveedor, ''), ''), 'compra', coalesce(nullif(c.cond_nombre, ''), 'contado'),
         c.total, 0, c.total, CASE WHEN cfg.ahora > c.vence THEN 'rojo' ELSE 'pendiente' END,
         CASE WHEN cfg.ahora > c.vence THEN 'FALTA COMPROBANTE de la compra' ELSE 'Compra sin comprobante' END, c.vence, 0, NULL, c.folio, c.total, c.proveedor, NULL, NULL, NULL
  FROM csr c, cfg
  UNION ALL
  SELECT 'cobro', c.id, c.fecha, c.hora, c.folio, c.usuario, c.forma || coalesce(' · ' || nullif(c.cliente, ''), ''), 'cobro', c.forma,
         c.importe, 0, c.importe, CASE WHEN cfg.ahora > c.vence THEN 'rojo' ELSE 'pendiente' END,
         CASE WHEN cfg.ahora > c.vence THEN 'FALTA ' || upper(CASE c.que WHEN 'voucher' THEN 'voucher' ELSE 'comprobante de ' || c.que END)
              ELSE 'Falta subir ' || CASE c.que WHEN 'voucher' THEN 'el voucher' ELSE 'el comprobante de ' || c.que END END,
         c.vence, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM cbr c, cfg)
