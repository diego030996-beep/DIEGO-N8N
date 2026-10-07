-- movimientos del polímero que se audita: entradas de Microsip (recepciones y compras que no vienen de una recepción) y consumo de las recetas
pol AS (SELECT a.articulo_id, a.clave, a.nombre, a.unidad FROM ms_articulos a, cfg
        WHERE a.base = cfg.base AND (a.nombre ~* cfg.auditar OR a.clave ~* cfg.auditar)
          AND EXISTS (SELECT 1 FROM prod_receta r WHERE r.base = cfg.base AND r.componente_id = a.articulo_id)),
ligm AS (SELECT DISTINCT coalesce(r.datos->>'DOCTO_CM_FTE_ID', r.datos->>'DOCTO_CM_ID_FTE') AS fte, coalesce(r.datos->>'DOCTO_CM_DEST_ID', r.datos->>'DOCTO_CM_ID_DEST') AS dst
         FROM ms_raw r, cfg WHERE r.base = cfg.base AND r.tabla = 'DOCTOS_CM_LIGAS'),
entm AS (
  SELECT (d.datos->>'ARTICULO_ID')::bigint AS articulo_id, coalesce(h.fecha, left(h.datos->>'FECHA', 10)::date) AS fecha, h.datos->>'FOLIO' AS folio,
         CASE WHEN (d.datos->>'UNIDADES') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'UNIDADES')::numeric ELSE 0 END * CASE WHEN upper(h.datos->>'TIPO_DOCTO') = 'D' THEN -1 ELSE 1 END AS kg
  FROM ms_raw h CROSS JOIN cfg JOIN ms_raw d ON d.base = h.base AND d.tabla = 'DOCTOS_CM_DET' AND d.datos->>'DOCTO_CM_ID' = h.datos->>'DOCTO_CM_ID'
  WHERE h.base = cfg.base AND h.tabla = 'DOCTOS_CM' AND upper(coalesce(h.datos->>'TIPO_DOCTO', '')) IN ('R', 'C', 'D') AND upper(coalesce(h.datos->>'ESTATUS', '')) <> 'C'
    AND (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z' AND (d.datos->>'ARTICULO_ID')::bigint IN (SELECT articulo_id FROM pol)
    AND NOT (upper(h.datos->>'TIPO_DOCTO') = 'C' AND EXISTS (SELECT 1 FROM ligm JOIN ms_raw x ON x.base = h.base AND x.tabla = 'DOCTOS_CM' AND x.datos->>'DOCTO_CM_ID' = ligm.fte
                                                              AND upper(x.datos->>'TIPO_DOCTO') = 'R' WHERE ligm.dst = h.datos->>'DOCTO_CM_ID'))),
usom AS (  -- consumo por receta y, si se pesó el tinaco, cuánto se fue de más (o de menos) contra la receta
  SELECT d.componente_id AS articulo_id, r.fecha, r.creado, r.id AS registro_id, r.articulo_id AS tinaco_id, r.cantidad AS piezas, d.cantidad AS kg,
         CASE WHEN r.peso_real IS NOT NULL THEN (r.peso_real - d.cantidad / nullif(r.cantidad, 0)) * r.cantidad END AS exceso
  FROM prod_registro r JOIN prod_registro_det d ON d.registro_id = r.id CROSS JOIN cfg
  WHERE r.base = cfg.base AND d.componente_id IN (SELECT articulo_id FROM pol))
