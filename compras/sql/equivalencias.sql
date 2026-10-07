-- Presentaciones: las que ya cuentan (confirmadas en la página o del archivo de equivalencias de Microsip) y sugerencias por revisar.
-- Una sugerencia NUNCA cuenta hasta que la confirmes. p = {}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*EQV*/,
art AS (SELECT a.articulo_id, a.clave, a.nombre, a.unidad, coalesce(a.linea, '') AS linea,
               translate(upper(coalesce(a.nombre, '')), 'ÁÉÍÓÚÜÑ', 'AEIOUUN') AS n
        FROM ms_articulos a, cfg WHERE a.base = cfg.base AND upper(coalesce(a.estatus, '')) <> 'B'),
pg AS (  -- artículos que parecen presentación: tonelada, millar, viaje, bulto/saco con contenido, metros
  SELECT art.*, CASE WHEN n ~ 'TONELADA' THEN 'TONELADA' WHEN n ~ 'MILLAR' THEN 'MILLAR' WHEN n ~ '\mVIAJE' THEN 'VIAJE'
                     WHEN n ~ '\m[0-9]+ *(METROS|MTS?)\M' AND n ~ '(ARENA|GRAVA|TEZONTLE|TEPETATE|GRANZON)' THEN 'VIAJE' END AS tipo
  FROM art),
tk AS (  -- palabras de cada nombre, sin palabras de presentación ni de relleno ("25 KG" = "25KG"; lo que va entre paréntesis no cuenta)
  SELECT art.articulo_id, array_agg(DISTINCT w ORDER BY w) AS w
  FROM art, regexp_split_to_table(regexp_replace(regexp_replace(
         -- en agregados "ARENA 3 METROS" el número es el tamaño del viaje, no una medida del producto
         CASE WHEN art.n ~ '(ARENA|GRAVA|TEZONTLE|TEPETATE|GRANZON)' THEN regexp_replace(art.n, '\m[0-9]+ *(METROS|MTS?)\M', ' ', 'g') ELSE art.n END,
         '\(.*?\)', ' ', 'g'), '([0-9]) +(KG|KGS|MT|MTS|LT|LTS|ML|M)\M', '\1\2', 'g'), '[^A-Z0-9/.]+') AS w
  WHERE w <> '' AND w !~ '^(DE|X|LA|EL|DEL|POR|PIEZAS?|PZAS?|TONELADA|TONELADAS|MILLAR|VIAJE|METROS|MTS|MT|BTO|BULTOS?)\Z'
  GROUP BY 1),
cand AS (  -- el artículo base: mismas medidas y a lo más una palabra distinta (la marca)
  SELECT p.articulo_id, p.clave, p.nombre, p.unidad, p.tipo, b.articulo_id AS base_id, b.clave AS base_clave, b.nombre AS base_nombre, b.unidad AS base_unidad,
         -- factor sugerido: lo que diga el nombre; si no se puede saber, queda vacío para que lo escribas
         CASE WHEN p.n ~ '\(([0-9]+) *(BTO|BULTOS?|SACOS?|PZAS?|PIEZAS?)\)' THEN substring(p.n FROM '\(([0-9]+) *(?:BTO|BULTOS?|SACOS?|PZAS?|PIEZAS?)\)')::numeric
              WHEN p.tipo = 'MILLAR' THEN 1000
              WHEN p.tipo = 'TONELADA' AND p.n ~ '\m([0-9]+) *KG' THEN round(1000 / substring(p.n FROM '\m([0-9]+) *KG')::numeric, 2)
              WHEN p.tipo = 'VIAJE' AND p.n ~ '\m([0-9]+) *(METROS|MTS?)\M' THEN substring(p.n FROM '\m([0-9]+) *(?:METROS|MTS?)\M')::numeric END AS factor,
         row_number() OVER (PARTITION BY p.articulo_id ORDER BY cardinality(ARRAY(SELECT unnest(tp.w) EXCEPT SELECT unnest(tb.w)))
                                                         + cardinality(ARRAY(SELECT unnest(tb.w) EXCEPT SELECT unnest(tp.w))), length(b.n)) AS rk
  FROM pg p JOIN tk tp ON tp.articulo_id = p.articulo_id
  JOIN art b ON b.articulo_id <> p.articulo_id AND b.n !~ '(TONELADA|MILLAR|\mVIAJE\M)'
  JOIN tk tb ON tb.articulo_id = b.articulo_id
  WHERE p.tipo IS NOT NULL
    -- mismas medidas y números
    AND ARRAY(SELECT x FROM unnest(tp.w) x WHERE x ~ '[0-9]' ORDER BY 1) = ARRAY(SELECT x FROM unnest(tb.w) x WHERE x ~ '[0-9]' ORDER BY 1)
    -- al menos dos palabras en común y a lo más una distinta en total
    AND cardinality(ARRAY(SELECT unnest(tp.w) INTERSECT SELECT unnest(tb.w))) >= CASE WHEN p.tipo = 'VIAJE' THEN 1 ELSE 2 END
    AND cardinality(ARRAY(SELECT unnest(tp.w) EXCEPT SELECT unnest(tb.w))) + cardinality(ARRAY(SELECT unnest(tb.w) EXCEPT SELECT unnest(tp.w))) <= 1)
SELECT json_build_object('ok', true,
  'activas', (SELECT coalesce(json_agg(json_build_object('articulo_id', q.articulo_id, 'clave', a.clave, 'articulo', a.nombre, 'unidad', a.unidad,
              'base_id', q.base_id, 'base_clave', b.clave, 'base_articulo', b.nombre, 'base_unidad', b.unidad, 'factor', q.factor,
              'origen', coalesce(e.origen, 'archivo de equivalencias (Microsip)'), 'por', e.por) ORDER BY b.nombre, a.nombre), '[]'::json)
              FROM eqv q CROSS JOIN cfg
              JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = q.articulo_id
              JOIN ms_articulos b ON b.base = cfg.base AND b.articulo_id = q.base_id
              LEFT JOIN compras_equivalencias e ON e.base = cfg.base AND e.articulo_id = q.articulo_id),
  'rechazadas', (SELECT coalesce(json_agg(json_build_object('articulo_id', e.articulo_id, 'articulo', a.nombre)), '[]'::json)
              FROM compras_equivalencias e CROSS JOIN cfg LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = e.articulo_id
              WHERE e.base = cfg.base AND NOT e.confirmado),
  'sugeridas', (SELECT coalesce(json_agg(json_build_object('articulo_id', c.articulo_id, 'clave', c.clave, 'articulo', c.nombre, 'unidad', c.unidad,
              'tipo', c.tipo, 'base_id', c.base_id, 'base_clave', c.base_clave, 'base_articulo', c.base_nombre, 'base_unidad', c.base_unidad,
              'factor', c.factor) ORDER BY c.tipo, c.nombre), '[]'::json)
              FROM cand c, cfg WHERE c.rk = 1
                AND NOT EXISTS (SELECT 1 FROM eqv WHERE eqv.articulo_id = c.articulo_id)
                AND NOT EXISTS (SELECT 1 FROM compras_equivalencias e WHERE e.base = cfg.base AND e.articulo_id = c.articulo_id)),
  'sin_base', (SELECT coalesce(json_agg(json_build_object('articulo_id', p.articulo_id, 'clave', p.clave, 'articulo', p.nombre, 'unidad', p.unidad, 'tipo', p.tipo)
              ORDER BY p.nombre), '[]'::json)
              FROM pg p, cfg WHERE p.tipo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM cand c WHERE c.articulo_id = p.articulo_id)
                AND NOT EXISTS (SELECT 1 FROM eqv WHERE eqv.articulo_id = p.articulo_id)
                AND NOT EXISTS (SELECT 1 FROM compras_equivalencias e WHERE e.base = cfg.base AND e.articulo_id = p.articulo_id))) AS r
FROM cfg;
