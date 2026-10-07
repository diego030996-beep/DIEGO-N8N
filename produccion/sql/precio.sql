-- Precio de venta para la simulación (vacío = el de lista de Microsip). p = {articulo_id, precio}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
DELETE FROM prod_precio x USING cfg WHERE x.base = cfg.base AND x.articulo_id = (cfg.p->>'articulo_id')::bigint AND coalesce(cfg.p->>'precio', '') = '';
WITH /*CTX*/
INSERT INTO prod_precio (base, articulo_id, precio, por)
SELECT cfg.base, (cfg.p->>'articulo_id')::bigint, (cfg.p->>'precio')::numeric, cfg.por FROM cfg WHERE coalesce(cfg.p->>'precio', '') <> ''
ON CONFLICT (base, articulo_id) DO UPDATE SET precio = EXCLUDED.precio, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true) AS r FROM cfg;
