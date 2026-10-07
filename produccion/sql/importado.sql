-- Confirma que un exporte ya se importó en Microsip (desde ahí la existencia de Microsip ya trae esos movimientos). p = {exporte_id, quitar: 'si'|''}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/,
u AS (UPDATE prod_exporte x SET importado = CASE WHEN cfg.p->>'quitar' = 'si' THEN NULL ELSE now() END, importado_por = cfg.por
      FROM cfg WHERE x.base = cfg.base AND x.id = (cfg.p->>'exporte_id')::bigint RETURNING x.id)
SELECT json_build_object('ok', (SELECT count(*) FROM u) > 0) AS r FROM cfg;
