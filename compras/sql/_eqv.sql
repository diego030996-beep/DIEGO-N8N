eqv AS (  -- presentaciones confirmadas: 1 artículo = factor × artículo base (la página manda sobre el archivo de Microsip)
  SELECT e.articulo_id, e.articulo_base_id AS base_id, e.factor FROM compras_equivalencias e, cfg
  WHERE e.base = cfg.base AND e.confirmado AND e.factor > 0 AND e.articulo_id <> e.articulo_base_id
  UNION ALL
  SELECT z.articulo_id, z.base_id, z.factor FROM (
    SELECT CASE WHEN r.pk ~ '^[0-9]{1,18}\Z' THEN r.pk::bigint END AS articulo_id,
           CASE WHEN (r.datos->>'ARTICULO_BASE_ID') ~ '^[0-9]{1,18}\Z' THEN (r.datos->>'ARTICULO_BASE_ID')::bigint END AS base_id,
           CASE WHEN (r.datos->>'FACTOR') ~ '^[0-9]+(\.[0-9]+)?\Z' THEN (r.datos->>'FACTOR')::numeric END AS factor
    FROM ms_raw r, cfg WHERE r.base = cfg.base AND r.tabla = 'COSTOS_ARTICULOS') z, cfg
  WHERE z.articulo_id IS NOT NULL AND z.base_id IS NOT NULL AND z.factor > 0 AND z.articulo_id <> z.base_id
    AND NOT EXISTS (SELECT 1 FROM compras_equivalencias x WHERE x.base = cfg.base AND x.articulo_id = z.articulo_id))