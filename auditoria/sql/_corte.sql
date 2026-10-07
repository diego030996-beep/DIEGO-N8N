f AS (SELECT coalesce(nullif(p->>'fecha', '')::date, hoy) AS d FROM cfg),
tc AS (   -- todo lo cobrado en caja ese día, por forma (incluye efectivo); devoluciones restan
  SELECT coalesce(fc.datos->>'NOMBRE', 'Forma ' || (c.datos->>'FORMA_COBRO_ID')) AS forma, v.docto_id, upper(v.tipo) AS tipo,
         CASE WHEN upper(v.tipo) = 'D' THEN -1 ELSE 1 END * CASE WHEN upper(coalesce(c.datos->>'TIPO', 'C')) = 'A' THEN -1 ELSE 1 END
           * CASE WHEN jsonb_typeof(c.datos->'IMPORTE') = 'number' THEN (c.datos->>'IMPORTE')::numeric ELSE 0 END AS importe
  FROM ms_ventas_v v CROSS JOIN cfg CROSS JOIN f
  CROSS JOIN LATERAL (SELECT c.datos FROM ms_raw c WHERE c.base = v.base AND c.tabla = 'DOCTOS_PV_COBROS' AND (c.datos->>'DOCTO_PV_ID') = v.docto_id::text) c
  LEFT JOIN ms_raw fc ON fc.base = v.base AND fc.tabla = 'FORMAS_COBRO' AND fc.pk = c.datos->>'FORMA_COBRO_ID'
  WHERE v.base = cfg.base AND v.origen = 'PV' AND upper(v.tipo) IN ('V', 'P', 'D') AND NOT v.cancelado AND v.fecha = f.d),
kd AS (   -- estado de cada cobro que pide comprobante
  SELECT k.forma, k.importe, coalesce(e.estado, m.estado, CASE WHEN EXISTS (SELECT 1 FROM ign WHERE ign.tipo = 'cobro' AND ign.ref = k.id) THEN 'ignorado' END) AS estado
  FROM cob k CROSS JOIN f LEFT JOIN est e ON e.cobro_id = k.id LEFT JOIN mov m ON m.clase = 'cobro' AND m.ref = k.id
  WHERE k.fecha = f.d),
formas AS (
  SELECT t.forma, count(DISTINCT t.docto_id) FILTER (WHERE t.tipo <> 'D') AS tickets, sum(t.importe) AS importe,
         (cfg.formas_sin <> '' AND t.forma ~* cfg.formas_sin) OR NOT (cfg.formas = '' OR t.forma ~* cfg.formas) AS sin_comprobante,
         (SELECT count(*) FROM kd WHERE kd.forma = t.forma AND kd.estado = 'verde') AS ok,
         (SELECT count(*) FROM kd WHERE kd.forma = t.forma AND kd.estado NOT IN ('verde', 'ignorado')) AS faltan,
         (SELECT coalesce(sum(kd.importe), 0) FROM kd WHERE kd.forma = t.forma AND kd.estado NOT IN ('verde', 'ignorado')) AS faltan_monto,
         (SELECT count(*) FROM kd WHERE kd.forma = t.forma AND kd.estado = 'ignorado') AS ignorados
  FROM tc t, cfg GROUP BY t.forma, cfg.formas_sin, cfg.formas),
rt AS (   -- todos los retiros del día, también los que no piden comprobante
  SELECT v.docto_id::text AS id, v.folio, left(coalesce(v.hora, ''), 5) AS hora, trim(coalesce(v.descripcion, '')) AS descripcion, coalesce(v.usuario, '') AS usuario,
         coalesce(nullif((SELECT abs(sum(CASE WHEN jsonb_typeof(c.datos->'IMPORTE') = 'number' THEN (c.datos->>'IMPORTE')::numeric ELSE 0 END))
                          FROM ms_raw c WHERE c.base = v.base AND c.tabla = 'DOCTOS_PV_COBROS' AND c.datos->>'DOCTO_PV_ID' = v.docto_id::text), 0), abs(coalesce(v.total, 0))) AS importe,
         (cfg.excl <> '' AND coalesce(v.descripcion, '') ~* cfg.excl) AS exento
  FROM ms_ventas_v v CROSS JOIN cfg CROSS JOIN f
  WHERE v.base = cfg.base AND v.origen = 'PV' AND upper(v.tipo) = 'R' AND NOT v.cancelado AND v.fecha = f.d),
dd AS (SELECT d.* FROM mov_retiro_dueno d, cfg, f WHERE d.base = cfg.base AND d.fecha = f.d AND NOT d.anulado),
-- los días antes de empezar la auditoría ("Auditar desde") solo se muestran: no se dicen comprobados ni pendientes
rts AS (SELECT rt.*, CASE WHEN dd.id IS NOT NULL THEN 'dueno' WHEN rt.exento THEN 'exento'
                          ELSE coalesce(e.estado, m.estado, CASE WHEN (SELECT d FROM f) < (SELECT desde FROM cfg) THEN 'sin_auditar' ELSE 'pendiente' END) END AS estado,
               coalesce(CASE WHEN dd.id IS NOT NULL THEN 'Retiro del dueño RD-' || dd.id END, e.motivo, m.motivo, CASE WHEN rt.exento THEN 'No pide comprobante' END) AS motivo,
               e.tipo, e.cm_folio, e.id AS registro_id
        FROM rt LEFT JOIN dd ON dd.retiro_id = rt.id LEFT JOIN est e ON e.retiro_id = rt.id LEFT JOIN mov m ON m.clase = 'retiro' AND m.ref = rt.id),
efe AS (SELECT coalesce(sum(importe) FILTER (WHERE sin_comprobante AND forma ~* 'efectivo|cambio'), 0) AS ventas FROM formas),
pend AS (SELECT count(*) AS n, coalesce(sum(greatest(falta, 0)), 0) AS monto FROM mov, f WHERE mov.fecha = f.d AND mov.estado <> 'verde'),
tot AS (   -- efectivo neto = efectivo cobrado − retiros de Microsip − retiros del dueño que no se capturaron en Microsip
  SELECT (SELECT coalesce(sum(importe), 0) FROM formas) AS vendido, (SELECT ventas FROM efe) AS efectivo_ventas,
         (SELECT coalesce(sum(importe), 0) FROM rt) AS retiros, (SELECT coalesce(sum(importe), 0) FROM rt WHERE exento) AS retiros_exentos,
         (SELECT coalesce(sum(importe), 0) FROM dd) AS retiros_dueno, (SELECT coalesce(sum(importe), 0) FROM dd WHERE retiro_id IS NULL) AS dueno_fuera,
         (SELECT ventas FROM efe) - (SELECT coalesce(sum(importe), 0) FROM rt) - (SELECT coalesce(sum(importe), 0) FROM dd WHERE retiro_id IS NULL) AS efectivo_neto)
