exi AS (  -- existencia (las presentaciones se suman al artículo base) y desglose por almacén
  SELECT coalesce(q.base_id, e.articulo_id) AS articulo_id, sum(coalesce(e.existencia, 0) * coalesce(q.factor, 1)) AS e,
         string_agg(trim(coalesce(e.almacen, '?')) || ': ' || round(coalesce(e.existencia, 0), 2), ' · ' ORDER BY e.almacen) AS por_almacen,
         bool_or(coalesce(e.existencia, 0) < 0) AS algun_negativo
  FROM ms_existencias e CROSS JOIN cfg LEFT JOIN eqv q ON q.articulo_id = e.articulo_id
  WHERE e.base = cfg.base AND (cfg.alm = '' OR coalesce(e.almacen, '') ~* cfg.alm) GROUP BY 1),
seg AS (SELECT s.docto_cm_id, s.estado FROM compras_oc_seguimiento s, cfg WHERE s.base = cfg.base),
recd AS MATERIALIZED (  -- lo recibido de cada OC: renglones de las recepciones/compras ligadas a ella
  SELECT lig.fte AS oc_id, z.articulo_id, sum(z.u) AS u FROM lig
  JOIN (SELECT d.datos->>'DOCTO_CM_ID' AS id,
               CASE WHEN (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z' THEN (d.datos->>'ARTICULO_ID')::bigint END AS articulo_id,
               CASE WHEN (d.datos->>'UNIDADES') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'UNIDADES')::numeric ELSE 0 END AS u
        FROM ms_raw d, cfg WHERE d.base = cfg.base AND d.tabla = 'DOCTOS_CM_DET'
          AND d.datos->>'DOCTO_CM_ID' IN (SELECT dst FROM lig WHERE fte IN (SELECT id FROM ids))) z ON z.id = lig.dst
  WHERE lig.fte IN (SELECT id FROM ids) GROUP BY 1, 2),
ocl0 AS (  -- lo recibido de cada renglón: lo que dice Microsip en la OC, o las recepciones ligadas (lo mayor)
  SELECT o.id, o.folio, o.fecha, o.prov, d.articulo_id, d.u AS pedido,
         greatest(coalesce(r.u, 0), coalesce(d.rec_ms, 0)) AS rec_lig, d.rec_ms, coalesce(r.u, 0) AS rec_ligado,
         EXISTS (SELECT 1 FROM lig WHERE lig.fte = o.id) AS ligada,
         coalesce(ltp.dias, cfg.ent_def) AS lt, seg.estado AS seg, o.estatus
  FROM oc o JOIN ocd d ON d.id = o.id CROSS JOIN cfg
  LEFT JOIN recd r ON r.oc_id = o.id AND r.articulo_id = d.articulo_id
  LEFT JOIN ltp ON ltp.prov = o.prov
  LEFT JOIN seg ON seg.docto_cm_id = o.id),
suel AS (  -- recepciones/compras capturadas SIN ligar, para OCs que nunca se ligaron y sin dato de Microsip (mismo proveedor y artículo)
  SELECT h.datos->>'PROVEEDOR_ID' AS prov, z.articulo_id, coalesce(h.fecha, left(h.datos->>'FECHA', 10)::date) AS fecha, sum(z.u) AS u
  FROM ms_raw h CROSS JOIN cfg
  JOIN (SELECT d.datos->>'DOCTO_CM_ID' AS id, (d.datos->>'ARTICULO_ID')::bigint AS articulo_id,
               CASE WHEN (d.datos->>'UNIDADES') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'UNIDADES')::numeric ELSE 0 END AS u
        FROM ms_raw d, cfg WHERE d.base = cfg.base AND d.tabla = 'DOCTOS_CM_DET' AND (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z') z
    ON z.id = h.datos->>'DOCTO_CM_ID'
  WHERE h.base = cfg.base AND h.tabla = 'DOCTOS_CM' AND upper(coalesce(h.datos->>'TIPO_DOCTO', '')) IN ('R', 'C')
    AND upper(coalesce(h.datos->>'ESTATUS', '')) <> 'C'
    AND coalesce(h.fecha, left(h.datos->>'FECHA', 10)::date) >= (SELECT min(fecha) FROM ocl0 WHERE pedido > rec_lig AND rec_ms IS NULL AND NOT ligada)
    AND NOT EXISTS (SELECT 1 FROM lig WHERE lig.dst = h.datos->>'DOCTO_CM_ID')
    AND EXISTS (SELECT 1 FROM ocl0 WHERE ocl0.prov = h.datos->>'PROVEEDOR_ID' AND ocl0.articulo_id = z.articulo_id AND ocl0.pedido > ocl0.rec_lig
                AND ocl0.rec_ms IS NULL AND NOT ocl0.ligada)
  GROUP BY 1, 2, 3),
ocl1 AS (  -- lo suelto se reparte a las OCs pendientes más viejas primero (solo lo recibido desde la fecha de cada OC)
  SELECT x.*, least(x.pedido - x.rec_lig, greatest(
           coalesce((SELECT sum(s.u) FROM suel s WHERE s.prov = x.prov AND s.articulo_id = x.articulo_id AND s.fecha >= x.fecha), 0)
           - coalesce(sum(x.pedido - x.rec_lig) OVER (PARTITION BY x.prov, x.articulo_id ORDER BY x.fecha, x.id
                                                     ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0), 0)) AS rec_suelto
  FROM ocl0 x WHERE x.pedido > x.rec_lig AND x.rec_ms IS NULL AND NOT x.ligada
  UNION ALL
  SELECT x.*, 0 FROM ocl0 x WHERE NOT (x.pedido > x.rec_lig AND x.rec_ms IS NULL AND NOT x.ligada)),
ocl AS (  -- renglones de OC con lo pedido, lo recibido y lo que falta, y el estado de la orden
  SELECT x.id, x.folio, x.fecha, x.prov, x.articulo_id, x.pedido, x.rec_lig + x.rec_suelto AS recibido, x.rec_suelto,
         x.estatus, x.rec_ms, x.rec_ligado, x.ligada,
         greatest(x.pedido - x.rec_lig - x.rec_suelto, 0) AS falta, x.lt,
         CASE WHEN x.estatus IN ('S', 'R') OR x.seg IN ('cancelada', 'recibida') THEN 'cerrada'
              WHEN x.pedido - x.rec_lig - x.rec_suelto <= 0 THEN 'completa'
              WHEN x.fecha >= cfg.hoy - (x.lt + cfg.gracia)::int
                THEN CASE WHEN x.rec_lig + x.rec_suelto > 0 THEN 'parcial' ELSE 'abierta' END
              WHEN x.seg = 'en_camino' THEN 'atrasada_confirmada'
              ELSE 'atrasada' END AS estado
  FROM ocl1 x CROSS JOIN cfg),
pend AS (  -- por recibir: abiertas, parciales (lo que falta) y atrasadas que confirmaste; las atrasadas sin confirmar van aparte
  SELECT coalesce(q.base_id, l.articulo_id) AS articulo_id,
         sum(l.falta * coalesce(q.factor, 1)) FILTER (WHERE l.estado IN ('abierta', 'parcial', 'atrasada_confirmada')) AS u,
         string_agg(DISTINCT l.folio || CASE WHEN l.estado = 'parcial' THEN ' (parcial)' WHEN l.estado = 'atrasada_confirmada' THEN ' (atrasada)' ELSE '' END, ', ')
           FILTER (WHERE l.estado IN ('abierta', 'parcial', 'atrasada_confirmada')) AS folios,
         sum(l.falta * coalesce(q.factor, 1)) FILTER (WHERE l.estado = 'atrasada') AS atr_u,
         string_agg(DISTINCT l.folio || ' del ' || to_char(l.fecha, 'DD/MM'), ', ') FILTER (WHERE l.estado = 'atrasada') AS atr_folios
  FROM ocl l LEFT JOIN eqv q ON q.articulo_id = l.articulo_id
  WHERE l.estado NOT IN ('cerrada', 'completa') GROUP BY 1)