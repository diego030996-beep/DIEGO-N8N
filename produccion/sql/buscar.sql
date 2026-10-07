-- Buscar artículos del inventario (para armar recetas). p = {q}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/,
exi AS (SELECT e.articulo_id, sum(coalesce(e.existencia, 0)) AS e FROM ms_existencias e, cfg WHERE e.base = cfg.base GROUP BY 1),
pal AS (SELECT w FROM cfg, regexp_split_to_table(upper(trim(cfg.p->>'q')), '\s+') AS w WHERE w <> '')
SELECT json_build_object('ok', true, 'articulos', (SELECT coalesce(json_agg(z), '[]'::json) FROM (
  SELECT a.articulo_id, a.clave, a.nombre, a.unidad, a.linea, coalesce(exi.e, 0) AS existencia, a.costo_ultimo AS costo
  FROM ms_articulos a CROSS JOIN cfg LEFT JOIN exi ON exi.articulo_id = a.articulo_id
  WHERE a.base = cfg.base AND coalesce(a.estatus, 'A') <> 'B'
    AND NOT EXISTS (SELECT 1 FROM pal WHERE (upper(coalesce(a.nombre, '')) || ' ' || upper(coalesce(a.clave, ''))) NOT LIKE '%' || pal.w || '%')
    AND EXISTS (SELECT 1 FROM pal)
  ORDER BY (upper(a.clave) = upper(trim(cfg.p->>'q'))) DESC, coalesce(exi.e, 0) > 0 DESC, a.nombre LIMIT 30) z)) AS r
FROM cfg;
