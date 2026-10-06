-- Limpieza del catálogo: artículos que se vendieron una sola vez y posibles duplicados (mismo producto, cambia solo la marca).
-- p = {ver_revisados: 'si'|''}. Las medidas, números, colores y palabras de "palabras_distintas" nunca cuentan como marca.
SET LOCAL statement_timeout = '45s';
WITH /*CTX*/,
ms AS (SELECT max(mes) AS mes FROM compras_maxmin, cfg WHERE compras_maxmin.base = cfg.base AND mes <= cfg.hoy),
mm AS (SELECT x.* FROM compras_maxmin x, cfg, ms WHERE x.base = cfg.base AND x.mes = ms.mes),
/*EXCL*/,
ex AS (SELECT e.articulo_id, sum(coalesce(e.existencia, 0)) AS e FROM ms_existencias e, cfg
       WHERE e.base = cfg.base AND (cfg.alm = '' OR coalesce(e.almacen, '') ~* cfg.alm) GROUP BY 1),
rev AS (SELECT r.* FROM compras_revision r, cfg WHERE r.base = cfg.base),
ver AS (SELECT coalesce(p->>'ver_revisados', '') = 'si' AS todos FROM cfg),
una AS (
  SELECT mm.articulo_id, mm.clave, mm.articulo, mm.unidad, mm.clase, mm.unidades, mm.venta, mm.proveedor, coalesce(ex.e, 0) AS existencia,
         r.decision, r.por, r.fecha
  FROM mm LEFT JOIN ex USING (articulo_id)
  LEFT JOIN rev r ON r.articulo_id = mm.articulo_id AND r.tipo = 'una_venta'
  WHERE mm.tickets <= 1 AND NOT EXISTS (SELECT 1 FROM excl WHERE excl.articulo_id = mm.articulo_id)
    AND ((SELECT todos FROM ver) OR r.decision IS NULL)),
art AS (  -- candidatos a duplicado: con venta en los últimos meses o con existencia, sin excluidos
  SELECT a.articulo_id, a.clave, a.nombre, a.unidad, a.linea FROM ms_articulos a, cfg
  WHERE a.base = cfg.base AND NOT EXISTS (SELECT 1 FROM excl WHERE excl.articulo_id = a.articulo_id)
    AND (EXISTS (SELECT 1 FROM mm WHERE mm.articulo_id = a.articulo_id) OR EXISTS (SELECT 1 FROM ex WHERE ex.articulo_id = a.articulo_id AND ex.e > 0))),
prot AS (SELECT DISTINCT upper(trim(x)) AS w FROM cfg, regexp_split_to_table(cfg.palabras_distintas, '[,;|[:space:]]+') AS x WHERE trim(x) <> ''),
tk AS (SELECT DISTINCT a.articulo_id, w FROM art a,
         regexp_split_to_table(translate(upper(coalesce(a.nombre, '')), 'ÁÉÍÓÚÜÑ', 'AEIOUUN'), '[^A-Z0-9/."-]+') AS w WHERE w <> ''),
fa AS (SELECT articulo_id, array_agg(w ORDER BY w) AS arr FROM tk GROUP BY 1),
llaves AS (  -- el nombre completo y el nombre sin cada palabra que podría ser marca
  SELECT fa.articulo_id, array_to_string(fa.arr, ' ') AS k, NULL::text AS quitada FROM fa WHERE array_length(fa.arr, 1) >= 2
  UNION ALL
  SELECT fa.articulo_id, array_to_string(array_remove(fa.arr, w), ' '), w FROM fa, unnest(fa.arr) AS w
  WHERE array_length(fa.arr, 1) >= 3 AND w !~ '[0-9]' AND length(w) >= 3 AND w NOT IN (SELECT w FROM prot)),
gr0 AS (SELECT k, array_agg(DISTINCT articulo_id ORDER BY articulo_id) AS ids, array_agg(DISTINCT quitada) FILTER (WHERE quitada IS NOT NULL) AS marcas
        FROM llaves GROUP BY k HAVING count(DISTINCT articulo_id) >= 2 AND count(DISTINCT articulo_id) <= 8),
gr AS (SELECT DISTINCT ON (ids) * FROM gr0 ORDER BY ids, k),
miembros AS (
  SELECT gr.k, gr.marcas, a.articulo_id, a.clave, a.nombre AS articulo, a.unidad, mm.clase, mm.unidades, mm.venta, mm.tickets,
         coalesce(mm.proveedor, '') AS proveedor, coalesce(ex.e, 0) AS existencia, r.decision
  FROM gr CROSS JOIN unnest(gr.ids) AS i(articulo_id)
  JOIN art a ON a.articulo_id = i.articulo_id
  LEFT JOIN mm ON mm.articulo_id = i.articulo_id
  LEFT JOIN ex ON ex.articulo_id = i.articulo_id
  LEFT JOIN rev r ON r.articulo_id = i.articulo_id AND r.tipo = 'duplicado'),
grupos AS (
  SELECT k, max(marcas::text) AS marcas, sum(coalesce(venta, 0)) AS venta, bool_or(decision IS NULL) AS pendiente,
         json_agg(json_build_object('articulo_id', articulo_id, 'clave', clave, 'articulo', articulo, 'unidad', unidad, 'clase', clase,
                  'unidades', unidades, 'venta', venta, 'tickets', tickets, 'proveedor', proveedor, 'existencia', existencia, 'decision', decision)
                  ORDER BY venta DESC NULLS LAST) AS articulos
  FROM miembros GROUP BY k),
pausados AS (
  SELECT o.articulo_id, a.clave, a.nombre AS articulo, a.unidad, coalesce(ex.e, 0) AS existencia, o.nota, o.por, o.actualizado AS fecha,
         (SELECT string_agg(r.tipo, ',') FROM rev r WHERE r.articulo_id = o.articulo_id AND r.decision = 'se_va') AS tipos,
         (SELECT x.ultima_venta FROM compras_maxmin x WHERE x.base = cfg.base AND x.articulo_id = o.articulo_id AND x.ultima_venta IS NOT NULL
          ORDER BY x.mes DESC LIMIT 1) AS ultima_venta
  FROM compras_articulos o CROSS JOIN cfg
  LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = o.articulo_id
  LEFT JOIN ex ON ex.articulo_id = o.articulo_id
  WHERE o.base = cfg.base AND o.excluir)
SELECT json_build_object('ok', true, 'mes', (SELECT mes FROM ms)::text, 'meses_c', cfg.meses_c,
  'pausados', (SELECT coalesce(json_agg(pausados ORDER BY pausados.fecha DESC), '[]'::json) FROM pausados),
  'una_venta', (SELECT coalesce(json_agg(una ORDER BY una.existencia DESC, una.venta DESC), '[]'::json) FROM una),
  'duplicados', (SELECT coalesce(json_agg(json_build_object('llave', k, 'marcas', marcas, 'articulos', articulos) ORDER BY venta DESC), '[]'::json)
                 FROM (SELECT * FROM grupos WHERE pendiente OR (SELECT todos FROM ver) ORDER BY venta DESC LIMIT 150) g),
  'revisados', (SELECT json_object_agg(decision, n) FROM (SELECT decision, count(*) AS n FROM rev GROUP BY 1) z)) AS r
FROM cfg;
