-- Marca un retiro o compra de Microsip como "no requiere comprobación" (o lo regresa). p = {tipo: 'retiro' | 'compra' | 'cobro', ref, motivo, quitar}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/,
del AS (DELETE FROM mov_ignorado i USING cfg WHERE cfg.p->>'quitar' = 'si' AND i.base = cfg.base AND i.tipo = cfg.p->>'tipo' AND i.ref = cfg.p->>'ref' RETURNING 1),
ins AS (INSERT INTO mov_ignorado (base, tipo, ref, motivo, por) SELECT cfg.base, p->>'tipo', p->>'ref', p->>'motivo', cfg.por FROM cfg WHERE coalesce(p->>'quitar', '') <> 'si'
        ON CONFLICT (base, tipo, ref) DO UPDATE SET motivo = EXCLUDED.motivo, por = EXCLUDED.por, creado = now() RETURNING 1),
bit AS (INSERT INTO mov_bitacora (ref, accion, detalle, por)
        SELECT (p->>'tipo') || ':' || (p->>'ref'), CASE WHEN p->>'quitar' = 'si' THEN 'quitar no requiere' ELSE 'no requiere comprobación' END, nullif(p->>'motivo', ''), cfg.por FROM cfg RETURNING id)
SELECT json_build_object('ok', true, 'cambios', (SELECT count(*) FROM del) + (SELECT count(*) FROM ins), 'bit', (SELECT count(*) FROM bit)) AS r;
