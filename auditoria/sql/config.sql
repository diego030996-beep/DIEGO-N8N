-- Guarda la configuración (solo admin). p = {general: {clave: valor}}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/,
g AS (SELECT key, value FROM cfg, jsonb_each_text(cfg.p->'general')),
up AS (INSERT INTO mov_config (clave, valor, por) SELECT g.key, g.value, cfg.por FROM g, cfg
       ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor, por = EXCLUDED.por, actualizado = now() RETURNING clave)
SELECT json_build_object('ok', true, 'guardados', (SELECT count(*) FROM up)) AS r;
