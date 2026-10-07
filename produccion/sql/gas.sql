-- Guarda o borra una carga de gas. p = {fecha, litros, costo, nota} o {borrar: id}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/,
del AS (DELETE FROM prod_gas g USING cfg WHERE g.base = cfg.base AND g.id = nullif(cfg.p->>'borrar', '')::bigint RETURNING g.id),
ins AS (INSERT INTO prod_gas (base, fecha, litros, costo, nota, por)
        SELECT cfg.base, (p->>'fecha')::date, nullif(p->>'litros', '')::numeric, (p->>'costo')::numeric, nullif(p->>'nota', ''), cfg.por
        FROM cfg WHERE coalesce(p->>'borrar', '') = '' RETURNING id)
SELECT json_build_object('ok', true, 'id', (SELECT id FROM ins), 'borrados', (SELECT count(*) FROM del)) AS r FROM cfg;
