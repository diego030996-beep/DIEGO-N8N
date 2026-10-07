-- Regresa un artículo pausado ("se va" / excluido a mano): vuelve al cálculo y al planeador. p = {articulo_id}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
DELETE FROM compras_revision r USING cfg
WHERE r.base = cfg.base AND r.articulo_id = (cfg.p->>'articulo_id')::bigint AND r.decision = 'se_va';
WITH /*CTX*/
UPDATE compras_articulos o SET excluir = false, nota = 'Regresó de pausados', por = cfg.por, actualizado = now()
FROM cfg WHERE o.base = cfg.base AND o.articulo_id = (cfg.p->>'articulo_id')::bigint;
WITH /*CTX*/
DELETE FROM compras_politica x USING cfg
WHERE x.base = cfg.base AND x.articulo_id = (cfg.p->>'articulo_id')::bigint AND x.politica = 'pausar';
WITH /*CTX*/
SELECT json_build_object('ok', true, 'articulo_id', (cfg.p->>'articulo_id')::bigint) AS r FROM cfg;
