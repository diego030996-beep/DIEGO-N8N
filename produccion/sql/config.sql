-- Configuración general. p = {general: {clave: valor}}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
INSERT INTO prod_config (clave, valor, por)
SELECT k, v, cfg.por FROM cfg, jsonb_each_text(cfg.p->'general') AS e(k, v)
ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true) AS r FROM cfg;
