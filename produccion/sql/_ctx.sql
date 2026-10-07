b AS (SELECT coalesce(nullif($1, ''), (SELECT nullif(valor, '') FROM prod_config WHERE clave = 'base'),
                (SELECT base FROM ms_articulos GROUP BY base ORDER BY count(*) DESC LIMIT 1), '') AS base,
             coalesce(nullif($5, '')::date, (now() AT TIME ZONE 'America/Mexico_City')::date) AS hoy,
             $2::jsonb || coalesce((SELECT jsonb_object_agg(clave, valor) FROM prod_config WHERE coalesce(valor, '') <> ''), '{}'::jsonb) AS c,
             $4::jsonb AS p, $3::text AS por),
cfg AS (SELECT b.*, coalesce(nullif(c->>'lineas', ''), 'tinaco|cisterna') AS lineas, coalesce(c->>'almacenes', '') AS alm,
               coalesce(nullif(c->>'iva', '')::numeric, 16) AS iva, coalesce(c->>'empresa', '') AS empresa
        FROM b)
