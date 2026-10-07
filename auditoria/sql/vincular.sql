-- Vincula (o quita) a mano la compra de Microsip de un movimiento. p = {id, compra_id}  (compra_id vacío = quitar)
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/, /*MOV*/,
c AS (SELECT cmp.* FROM cmp, cfg WHERE cmp.id = nullif(cfg.p->>'compra_id', '')),
chk AS (SELECT CASE WHEN coalesce(p->>'compra_id', '') <> '' AND NOT EXISTS (SELECT 1 FROM c) THEN 'Esa compra no está en Microsip.'
                    WHEN coalesce(p->>'compra_id', '') <> '' AND EXISTS (SELECT 1 FROM mov_registro g WHERE g.base = cfg.base AND g.compra_id = p->>'compra_id' AND NOT g.borrado AND g.id <> (p->>'id')::bigint)
                      THEN 'Esa compra ya está vinculada a otro movimiento.' END AS err FROM cfg),
up AS (UPDATE mov_registro m SET compra_id = nullif(p->>'compra_id', '') FROM cfg
       WHERE m.base = cfg.base AND m.id = (p->>'id')::bigint AND NOT m.borrado AND (SELECT err FROM chk) IS NULL RETURNING m.id),
bit AS (INSERT INTO mov_bitacora (registro_id, accion, detalle, por)
        SELECT up.id, 'vincular', coalesce('compra ' || (SELECT folio FROM c), 'quitó la compra'), cfg.por FROM up, cfg RETURNING id)
SELECT json_build_object('ok', EXISTS (SELECT 1 FROM up), 'msg', coalesce((SELECT err FROM chk), 'No encontré ese movimiento.'), 'bit', (SELECT count(*) FROM bit)) AS r;
