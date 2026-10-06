ocd AS (
  SELECT d.datos->>'DOCTO_CM_ID' AS id, (d.datos->>'ARTICULO_ID')::bigint AS articulo_id,
         sum(CASE WHEN (d.datos->>'UNIDADES') ~ '^-?[0-9.]+$' THEN (d.datos->>'UNIDADES')::numeric ELSE 0 END) AS u,
         sum(CASE WHEN (d.datos->>'PRECIO_TOTAL_NETO') ~ '^-?[0-9.]+$' THEN (d.datos->>'PRECIO_TOTAL_NETO')::numeric ELSE 0 END) AS imp
  FROM ms_raw d, cfg
  WHERE d.base = cfg.base AND d.tabla = 'DOCTOS_CM_DET' AND (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}$'
    AND d.datos->>'DOCTO_CM_ID' IN (SELECT id FROM ids)
  GROUP BY 1, 2)
