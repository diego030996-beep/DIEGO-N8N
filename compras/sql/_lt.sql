rcp AS (SELECT r.datos->>'DOCTO_CM_ID' AS id, coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) AS fecha
        FROM ms_raw r, cfg WHERE r.base = cfg.base AND r.tabla = 'DOCTOS_CM' AND upper(coalesce(r.datos->>'TIPO_DOCTO', '')) IN ('R', 'C')
          AND upper(coalesce(r.datos->>'ESTATUS', '')) <> 'C'),
ltm AS (  -- días de entrega reales por proveedor: de la orden de compra a su primera recepción ligada (último año)
  SELECT o.prov, percentile_cont(0.5) WITHIN GROUP (ORDER BY z.dias) AS dias, max(z.dias) AS peor, count(*) AS n
  FROM (SELECT lig.fte, min(rcp.fecha) AS fr FROM lig JOIN rcp ON rcp.id = lig.dst GROUP BY 1) w
  JOIN oc o ON o.id = w.fte CROSS JOIN cfg
  CROSS JOIN LATERAL (SELECT greatest(w.fr - o.fecha, 0) AS dias) z
  WHERE o.fecha >= cfg.hoy - 365 GROUP BY 1),
ltp AS (  -- días de entrega que se usan: los que escribiste, si no los medidos (con 2 o más entregas), si no el de fábrica
  SELECT p.prov, cp.dias_entrega AS manual, round(ltm.dias::numeric, 1) AS medido, ltm.n, ltm.peor,
         coalesce(cp.dias_entrega, CASE WHEN ltm.n >= 2 THEN greatest(ceil(ltm.dias), 1) END) AS dias
  FROM (SELECT prov FROM ltm UNION SELECT cp2.proveedor_id FROM compras_proveedores cp2, cfg WHERE cp2.base = cfg.base) p
  CROSS JOIN cfg
  LEFT JOIN ltm ON ltm.prov = p.prov
  LEFT JOIN compras_proveedores cp ON cp.base = cfg.base AND cp.proveedor_id = p.prov)