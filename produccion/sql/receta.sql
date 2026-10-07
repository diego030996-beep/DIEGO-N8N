-- Guarda la receta de un tinaco (reemplaza la anterior). p = {articulo_id, comps: [{componente_id, cantidad}]}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
DELETE FROM prod_receta r USING cfg WHERE r.base = cfg.base AND r.articulo_id = (cfg.p->>'articulo_id')::bigint;
WITH /*CTX*/
INSERT INTO prod_receta (base, articulo_id, componente_id, cantidad, por)
SELECT cfg.base, (cfg.p->>'articulo_id')::bigint, (x->>'componente_id')::bigint, (x->>'cantidad')::numeric, cfg.por
FROM cfg, jsonb_array_elements(cfg.p->'comps') x WHERE (x->>'cantidad')::numeric > 0
ON CONFLICT (base, articulo_id, componente_id) DO UPDATE SET cantidad = EXCLUDED.cantidad, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true, 'articulo_id', (cfg.p->>'articulo_id')::bigint) AS r FROM cfg;
