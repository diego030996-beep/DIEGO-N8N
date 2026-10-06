-- Busca artículos para ajustar su configuración. p = {q}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/,
ms AS (SELECT max(mes) AS mes FROM compras_maxmin, cfg WHERE compras_maxmin.base = cfg.base AND mes <= cfg.hoy),
q AS (SELECT '%' || regexp_replace(trim(coalesce(p->>'q', '')), '\s+', '%', 'g') || '%' AS t FROM cfg)
SELECT json_build_object('ok', true, 'filas', (SELECT coalesce(json_agg(z), '[]'::json) FROM (
  SELECT a.articulo_id, a.clave, a.nombre AS articulo, a.unidad, mm.clase AS clase_calc, mm.minimo AS min_calc, mm.maximo AS max_calc,
         mm.proveedor_id AS prov_calc, mm.proveedor AS prov_nombre, mm.venta_diaria AS vd,
         o.proveedor_id, o.clase, o.empaque, o.minimo, o.maximo, o.excluir, o.nota
  FROM ms_articulos a CROSS JOIN cfg CROSS JOIN q
  LEFT JOIN compras_maxmin mm ON mm.base = cfg.base AND mm.mes = (SELECT mes FROM ms) AND mm.articulo_id = a.articulo_id
  LEFT JOIN compras_articulos o ON o.base = cfg.base AND o.articulo_id = a.articulo_id
  WHERE a.base = cfg.base AND (CASE WHEN coalesce(cfg.p->>'solo_ajustados', '') = 'si' THEN o.articulo_id IS NOT NULL
                                    ELSE length(q.t) > 3 AND (a.nombre ILIKE q.t OR a.clave ILIKE q.t) END)
  ORDER BY mm.venta DESC NULLS LAST, a.nombre LIMIT 60) z)) AS r
FROM cfg;
