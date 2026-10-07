-- Política de resurtido de un producto. p = {articulo_id, politica: 'minimo'|'bajo_pedido'|'pausar'|'' (quitar), minimo, nota}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
DELETE FROM compras_politica x USING cfg WHERE x.base = cfg.base AND x.articulo_id = (cfg.p->>'articulo_id')::bigint AND coalesce(cfg.p->>'politica', '') = '';
WITH /*CTX*/
INSERT INTO compras_politica (base, articulo_id, politica, minimo, nota, por)
SELECT cfg.base, (p->>'articulo_id')::bigint, p->>'politica', nullif(p->>'minimo', '')::numeric, nullif(p->>'nota', ''), cfg.por
FROM cfg WHERE coalesce(p->>'politica', '') <> ''
ON CONFLICT (base, articulo_id) DO UPDATE SET politica = EXCLUDED.politica, minimo = EXCLUDED.minimo, nota = EXCLUDED.nota, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true, 'articulo_id', (cfg.p->>'articulo_id')::bigint, 'politica', cfg.p->>'politica') AS r FROM cfg;
