-- Decisión de la limpieza del catálogo. p = {articulo_id, tipo: 'una_venta'|'duplicado', decision: 'queda'|'se_va'|'deshacer', grupo, nota}
-- "se_va" excluye el artículo (deja de calcularse y de aparecer en el planeador); "queda" lo deja como está.
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
DELETE FROM compras_revision r USING cfg
WHERE r.base = cfg.base AND r.articulo_id = (cfg.p->>'articulo_id')::bigint AND r.tipo = cfg.p->>'tipo' AND cfg.p->>'decision' = 'deshacer';
WITH /*CTX*/
INSERT INTO compras_revision (base, articulo_id, tipo, decision, grupo, nota, por)
SELECT cfg.base, (p->>'articulo_id')::bigint, p->>'tipo', p->>'decision', nullif(p->>'grupo', ''), nullif(p->>'nota', ''), cfg.por
FROM cfg WHERE p->>'decision' IN ('queda', 'se_va')
ON CONFLICT (base, articulo_id, tipo) DO UPDATE SET decision = EXCLUDED.decision, grupo = EXCLUDED.grupo, nota = EXCLUDED.nota,
  por = EXCLUDED.por, fecha = now();
WITH /*CTX*/
INSERT INTO compras_articulos (base, articulo_id, excluir, nota, por)
SELECT cfg.base, (p->>'articulo_id')::bigint, true,
       'Revisión: ' || CASE p->>'tipo' WHEN 'duplicado' THEN 'duplicado de otra marca' ELSE 'se vendió una sola vez' END
         || coalesce(' · ' || nullif(p->>'nota', ''), ''), cfg.por
FROM cfg WHERE p->>'decision' = 'se_va'
ON CONFLICT (base, articulo_id) DO UPDATE SET excluir = true, nota = EXCLUDED.nota, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
UPDATE compras_articulos o SET excluir = false, nota = NULL, por = cfg.por, actualizado = now()
FROM cfg WHERE o.base = cfg.base AND o.articulo_id = (cfg.p->>'articulo_id')::bigint AND p->>'decision' IN ('queda', 'deshacer')
  AND coalesce(o.nota, '') LIKE 'Revisión:%'
  AND NOT EXISTS (SELECT 1 FROM compras_revision r WHERE r.base = cfg.base AND r.articulo_id = o.articulo_id AND r.decision = 'se_va');
WITH /*CTX*/
SELECT json_build_object('ok', true, 'articulo_id', (cfg.p->>'articulo_id')::bigint, 'decision', cfg.p->>'decision') AS r FROM cfg;
