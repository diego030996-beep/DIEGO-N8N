-- Borra una captura (solo si no se ha exportado). p = {id}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/,
del AS (DELETE FROM prod_registro r USING cfg WHERE r.base = cfg.base AND r.id = (cfg.p->>'id')::bigint AND r.exporte_id IS NULL RETURNING r.id)
SELECT json_build_object('ok', (SELECT count(*) FROM del) > 0, 'msg', CASE WHEN (SELECT count(*) FROM del) = 0 THEN 'Ya se exportó: no se puede borrar.' END) AS r FROM cfg;
