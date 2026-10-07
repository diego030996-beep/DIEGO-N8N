exi AS (  -- existencia en Microsip (almacenes de la configuración; vacío = todos)
  SELECT e.articulo_id, sum(coalesce(e.existencia, 0)) AS e FROM ms_existencias e, cfg
  WHERE e.base = cfg.base AND (cfg.alm = '' OR coalesce(e.almacen, '') ~* cfg.alm) GROUP BY 1),
sinimp AS (  -- lo capturado que todavía no se ha importado a Microsip (sin exportar, o exportado pero sin confirmar que se importó)
  SELECT r.* FROM prod_registro r CROSS JOIN cfg LEFT JOIN prod_exporte x ON x.id = r.exporte_id
  WHERE r.base = cfg.base AND (r.exporte_id IS NULL OR x.importado IS NULL)),
cons AS (SELECT d.componente_id AS articulo_id, sum(d.cantidad) AS u FROM sinimp r JOIN prod_registro_det d ON d.registro_id = r.id GROUP BY 1),
fab AS (SELECT r.articulo_id, sum(r.cantidad) AS u FROM sinimp r GROUP BY 1),
ulc AS (  -- precio de la última compra (recepción o compra) de cada artículo: por si Microsip no tiene último costo
  SELECT DISTINCT ON (z.articulo_id) z.articulo_id, z.precio FROM (
    SELECT (d.datos->>'ARTICULO_ID')::bigint AS articulo_id, coalesce(h.fecha, left(h.datos->>'FECHA', 10)::date) AS fecha,
           CASE WHEN (d.datos->>'PRECIO_UNITARIO') ~ '^[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'PRECIO_UNITARIO')::numeric END AS precio
    FROM ms_raw h CROSS JOIN cfg JOIN ms_raw d ON d.base = h.base AND d.tabla = 'DOCTOS_CM_DET' AND d.datos->>'DOCTO_CM_ID' = h.datos->>'DOCTO_CM_ID'
    WHERE h.base = cfg.base AND h.tabla = 'DOCTOS_CM' AND upper(coalesce(h.datos->>'TIPO_DOCTO', '')) IN ('R', 'C')
      AND upper(coalesce(h.datos->>'ESTATUS', '')) <> 'C' AND (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z'
      AND (d.datos->>'ARTICULO_ID')::bigint IN (SELECT componente_id FROM prod_receta WHERE base = cfg.base)) z
  WHERE z.precio > 0 ORDER BY z.articulo_id, z.fecha DESC),
cos AS (SELECT a.articulo_id, coalesce(nullif(a.costo_ultimo, 0), ulc.precio) AS costo,
               CASE WHEN nullif(a.costo_ultimo, 0) IS NOT NULL THEN 'último costo' WHEN ulc.precio IS NOT NULL THEN 'última compra' END AS fuente
        FROM ms_articulos a CROSS JOIN cfg LEFT JOIN ulc ON ulc.articulo_id = a.articulo_id WHERE a.base = cfg.base)
