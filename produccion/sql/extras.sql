-- Gastos por tinaco que NO salen del inventario (solo simulación). p = {lista: [{concepto, monto, articulo_id|null}]} reemplaza todos
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
DELETE FROM prod_extra x USING cfg WHERE x.base = cfg.base;
WITH /*CTX*/
INSERT INTO prod_extra (base, concepto, monto, articulo_id, por)
SELECT cfg.base, x->>'concepto', (x->>'monto')::numeric, nullif(x->>'articulo_id', '')::bigint, cfg.por FROM cfg, jsonb_array_elements(cfg.p->'lista') x;
WITH /*CTX*/
SELECT json_build_object('ok', true) AS r FROM cfg;
