-- Copia la receta de un tinaco a otros (p. ej. el mismo modelo en otro color) cambiando un componente por otro (el polímero del color).
-- p = {de, a: [ids], cambiar_de, cambiar_a}   (cambiar_* opcionales)
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
DELETE FROM prod_receta r USING cfg WHERE r.base = cfg.base AND r.articulo_id IN (SELECT (v #>> '{}')::bigint FROM jsonb_array_elements(cfg.p->'a') v);
WITH /*CTX*/
INSERT INTO prod_receta (base, articulo_id, componente_id, cantidad, por)
SELECT cfg.base, (v #>> '{}')::bigint,
       CASE WHEN r.componente_id::text = coalesce(cfg.p->>'cambiar_de', '') AND coalesce(cfg.p->>'cambiar_a', '') <> '' THEN (cfg.p->>'cambiar_a')::bigint ELSE r.componente_id END,
       r.cantidad, cfg.por
FROM cfg JOIN prod_receta r ON r.base = cfg.base AND r.articulo_id = (cfg.p->>'de')::bigint, jsonb_array_elements(cfg.p->'a') v
WHERE (v #>> '{}')::bigint <> r.articulo_id
ON CONFLICT (base, articulo_id, componente_id) DO UPDATE SET cantidad = prod_receta.cantidad + EXCLUDED.cantidad, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true, 'copiados', jsonb_array_length(cfg.p->'a')) AS r FROM cfg;
