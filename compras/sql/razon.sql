-- Cambia la razón (y nota) de una decisión. p = {id, razon, nota}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
UPDATE compras_decisiones d SET razon = nullif(cfg.p->>'razon', ''), nota = nullif(cfg.p->>'nota', ''), por = cfg.por, modificado = now()
FROM compras_planes pl, cfg
WHERE d.id = (cfg.p->>'id')::bigint AND pl.id = d.plan_id AND pl.base = cfg.base;
WITH /*CTX*/
SELECT json_build_object('ok', true, 'id', d.id, 'razon', d.razon, 'nota', d.nota) AS r
FROM compras_decisiones d, cfg WHERE d.id = (cfg.p->>'id')::bigint;
