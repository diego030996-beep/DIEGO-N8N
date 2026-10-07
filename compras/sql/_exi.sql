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
ocl AS (  -- renglones de OC con lo pedido, lo recibido y lo que falta, y el estado de la orden
  SELECT o.id, o.folio, o.fecha, o.prov, d.articulo_id, d.u AS pedido, coalesce(r.u, 0) AS recibido,
         greatest(d.u - coalesce(r.u, 0), 0) AS falta, coalesce(ltp.dias, cfg.ent_def) AS lt,
         CASE WHEN o.estatus IN ('S', 'R') OR seg.estado IN ('cancelada', 'recibida') THEN 'cerrada'
              WHEN d.u - coalesce(r.u, 0) <= 0 THEN 'completa'
              WHEN o.fecha >= cfg.hoy - (coalesce(ltp.dias, cfg.ent_def) + cfg.gracia)::int
                THEN CASE WHEN coalesce(r.u, 0) > 0 THEN 'parcial' ELSE 'abierta' END
              WHEN seg.estado = 'en_camino' THEN 'atrasada_confirmada'
              ELSE 'atrasada' END AS estado
  FROM oc o JOIN ocd d ON d.id = o.id CROSS JOIN cfg
  LEFT JOIN recd r ON r.oc_id = o.id AND r.articulo_id = d.articulo_id
  LEFT JOIN ltp ON ltp.prov = o.prov
  LEFT JOIN seg ON seg.docto_cm_id = o.id),
pend AS (  -- por recibir: abiertas, parciales (lo que falta) y atrasadas que confirmaste; las atrasadas sin confirmar van aparte
  SELECT coalesce(q.base_id, l.articulo_id) AS articulo_id,
         sum(l.falta * coalesce(q.factor, 1)) FILTER (WHERE l.estado IN ('abierta', 'parcial', 'atrasada_confirmada')) AS u,
         string_agg(DISTINCT l.folio || CASE WHEN l.estado = 'parcial' THEN ' (parcial)' WHEN l.estado = 'atrasada_confirmada' THEN ' (atrasada)' ELSE '' END, ', ')
           FILTER (WHERE l.estado IN ('abierta', 'parcial', 'atrasada_confirmada')) AS folios,
         sum(l.falta * coalesce(q.factor, 1)) FILTER (WHERE l.estado = 'atrasada') AS atr_u,
         string_agg(DISTINCT l.folio || ' del ' || to_char(l.fecha, 'DD/MM'), ', ') FILTER (WHERE l.estado = 'atrasada') AS atr_folios
  FROM ocl l LEFT JOIN eqv q ON q.articulo_id = l.articulo_id
  WHERE l.estado NOT IN ('cerrada', 'completa') GROUP BY 1)