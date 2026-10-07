-- Política para varios productos a la vez. p = {articulos: [id, ...], politica: 'bajo_pedido'|'pausar'|'' (quitar), nota}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
DELETE FROM compras_politica x USING cfg
WHERE x.base = cfg.base AND coalesce(cfg.p->>'politica', '') = ''
  AND x.articulo_id IN (SELECT (v #>> '{}')::bigint FROM jsonb_array_elements(cfg.p->'articulos') v);
WITH /*CTX*/
INSERT INTO compras_politica (base, articulo_id, politica, minimo, nota, por)
SELECT cfg.base, (v #>> '{}')::bigint, cfg.p->>'politica', NULL, nullif(cfg.p->>'nota', ''), cfg.por
FROM cfg, jsonb_array_elements(cfg.p->'articulos') v WHERE coalesce(cfg.p->>'politica', '') <> ''
ON CONFLICT (base, articulo_id) DO UPDATE SET politica = EXCLUDED.politica, minimo = NULL, nota = EXCLUDED.nota, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true, 'n', jsonb_array_length(cfg.p->'articulos'), 'politica', cfg.p->>'politica') AS r FROM cfg;
