-- Control de materia prima: lo que entró (recepciones y compras de Microsip), lo que se consumió (capturas) y lo que hay. p = {desde, hasta}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*INV*/,
rg AS (SELECT coalesce(nullif(p->>'desde', '')::date, date_trunc('month', hoy)::date) AS d, coalesce(nullif(p->>'hasta', '')::date, hoy) AS h FROM cfg),
comp AS (SELECT DISTINCT r.componente_id AS articulo_id FROM prod_receta r, cfg WHERE r.base = cfg.base
         UNION SELECT DISTINCT d.componente_id FROM prod_registro_det d JOIN prod_registro r ON r.id = d.registro_id, cfg WHERE r.base = cfg.base),
lig AS (SELECT DISTINCT coalesce(r.datos->>'DOCTO_CM_FTE_ID', r.datos->>'DOCTO_CM_ID_FTE') AS fte, coalesce(r.datos->>'DOCTO_CM_DEST_ID', r.datos->>'DOCTO_CM_ID_DEST') AS dst
        FROM ms_raw r, cfg WHERE r.base = cfg.base AND r.tabla = 'DOCTOS_CM_LIGAS'),
doc AS (  -- recepciones (R) y compras (C) que no vienen de una recepción, sin canceladas, en el periodo
  SELECT h.datos->>'DOCTO_CM_ID' AS id, upper(h.datos->>'TIPO_DOCTO') AS tipo, coalesce(h.fecha, left(h.datos->>'FECHA', 10)::date) AS fecha, h.datos->>'FOLIO' AS folio,
         h.datos->>'PROVEEDOR_ID' AS prov
  FROM ms_raw h CROSS JOIN cfg CROSS JOIN rg
  WHERE h.base = cfg.base AND h.tabla = 'DOCTOS_CM' AND upper(coalesce(h.datos->>'TIPO_DOCTO', '')) IN ('R', 'C') AND upper(coalesce(h.datos->>'ESTATUS', '')) <> 'C'
    AND coalesce(h.fecha, left(h.datos->>'FECHA', 10)::date) BETWEEN rg.d AND rg.h
    AND NOT (upper(h.datos->>'TIPO_DOCTO') = 'C' AND EXISTS (SELECT 1 FROM lig JOIN ms_raw x ON x.base = h.base AND x.tabla = 'DOCTOS_CM' AND x.datos->>'DOCTO_CM_ID' = lig.fte
                                                             AND upper(x.datos->>'TIPO_DOCTO') = 'R' WHERE lig.dst = h.datos->>'DOCTO_CM_ID'))),
ent AS (
  SELECT (d.datos->>'ARTICULO_ID')::bigint AS articulo_id,
         sum(CASE WHEN (d.datos->>'UNIDADES') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'UNIDADES')::numeric ELSE 0 END) AS u,
         sum(CASE WHEN (d.datos->>'PRECIO_TOTAL_NETO') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (d.datos->>'PRECIO_TOTAL_NETO')::numeric ELSE 0 END) AS imp,
         json_agg(json_build_object('folio', doc.folio, 'fecha', doc.fecha, 'u', d.datos->>'UNIDADES', 'prov', p.datos->>'NOMBRE') ORDER BY doc.fecha) AS docs
  FROM doc JOIN ms_raw d ON d.tabla = 'DOCTOS_CM_DET' AND d.datos->>'DOCTO_CM_ID' = doc.id CROSS JOIN cfg
  LEFT JOIN ms_raw p ON p.base = cfg.base AND p.tabla = 'PROVEEDORES' AND p.pk = doc.prov
  WHERE d.base = cfg.base AND (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z' AND (d.datos->>'ARTICULO_ID')::bigint IN (SELECT articulo_id FROM comp)
  GROUP BY 1),
usa AS (SELECT d.componente_id AS articulo_id, sum(d.cantidad) AS u, sum(d.cantidad * coalesce(d.costo_unit, 0)) AS imp
        FROM prod_registro r JOIN prod_registro_det d ON d.registro_id = r.id CROSS JOIN cfg CROSS JOIN rg
        WHERE r.base = cfg.base AND r.fecha BETWEEN rg.d AND rg.h GROUP BY 1)
SELECT json_build_object('ok', true, 'desde', (SELECT d FROM rg), 'hasta', (SELECT h FROM rg),
  'filas', (SELECT coalesce(json_agg(json_build_object('articulo_id', a.articulo_id, 'clave', a.clave, 'nombre', a.nombre, 'unidad', a.unidad,
      'entro', coalesce(ent.u, 0), 'entro_imp', round(coalesce(ent.imp, 0), 2), 'docs', ent.docs, 'consumo', coalesce(usa.u, 0), 'consumo_imp', round(coalesce(usa.imp, 0), 2),
      'existencia', coalesce(exi.e, 0), 'por_importar', coalesce(cons.u, 0), 'disponible', coalesce(exi.e, 0) - coalesce(cons.u, 0), 'costo', cos.costo) ORDER BY a.nombre), '[]'::json)
    FROM comp JOIN ms_articulos a ON a.articulo_id = comp.articulo_id CROSS JOIN cfg
    LEFT JOIN ent ON ent.articulo_id = comp.articulo_id LEFT JOIN usa ON usa.articulo_id = comp.articulo_id
    LEFT JOIN exi ON exi.articulo_id = comp.articulo_id LEFT JOIN cons ON cons.articulo_id = comp.articulo_id LEFT JOIN cos ON cos.articulo_id = comp.articulo_id
    WHERE a.base = cfg.base)) AS r
FROM cfg;
