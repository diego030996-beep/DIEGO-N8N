ocd AS (
  SELECT d.datos->>'DOCTO_CM_ID' AS id, (d.datos->>'ARTICULO_ID')::bigint AS articulo_id,
         sum(CASE WHEN (d.datos->>'UNIDADES') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'UNIDADES')::numeric ELSE 0 END) AS u,
         sum(CASE WHEN (d.datos->>'PRECIO_TOTAL_NETO') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'PRECIO_TOTAL_NETO')::numeric ELSE 0 END) AS imp,
         -- lo que el propio Microsip lleva como recibido / por recibir en el renglón de la OC (si la copia trae esas columnas)
         sum(CASE WHEN (d.datos->>'UNIDADES_REC_DEV') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'UNIDADES_REC_DEV')::numeric END) AS rec_ms,
         sum(CASE WHEN (d.datos->>'UNIDADES_A_REC') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'UNIDADES_A_REC')::numeric END) AS arec_ms
  FROM ms_raw d, cfg
  WHERE d.base = cfg.base AND d.tabla = 'DOCTOS_CM_DET' AND (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z'
    AND d.datos->>'DOCTO_CM_ID' IN (SELECT id FROM ids)
  GROUP BY 1, 2)
