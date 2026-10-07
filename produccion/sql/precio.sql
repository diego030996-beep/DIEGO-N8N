-- Precios de venta del simulador: público (precio; vacío = el de lista de Microsip), distribuidor y Mercado Libre. p = {articulo_id, precio, dist, ml}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
DELETE FROM prod_precio x USING cfg WHERE x.base = cfg.base AND x.articulo_id = (cfg.p->>'articulo_id')::bigint
  AND coalesce(cfg.p->>'precio', '') = '' AND coalesce(cfg.p->>'dist', '') = '' AND coalesce(cfg.p->>'ml', '') = '';
WITH /*CTX*/
INSERT INTO prod_precio (base, articulo_id, precio, dist, ml, por)
SELECT cfg.base, (cfg.p->>'articulo_id')::bigint, nullif(cfg.p->>'precio', '')::numeric, nullif(cfg.p->>'dist', '')::numeric, nullif(cfg.p->>'ml', '')::numeric, cfg.por
FROM cfg WHERE coalesce(cfg.p->>'precio', '') <> '' OR coalesce(cfg.p->>'dist', '') <> '' OR coalesce(cfg.p->>'ml', '') <> ''
ON CONFLICT (base, articulo_id) DO UPDATE SET precio = EXCLUDED.precio, dist = EXCLUDED.dist, ml = EXCLUDED.ml, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true) AS r FROM cfg;
