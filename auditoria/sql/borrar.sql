-- Borra (oculta) un movimiento mal capturado. Solo admin. Queda en la bitácora. p = {id, nota}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/,
up AS (UPDATE mov_registro m SET borrado = true FROM cfg WHERE m.base = cfg.base AND m.id = (p->>'id')::bigint AND NOT m.borrado RETURNING m.id),
bit AS (INSERT INTO mov_bitacora (registro_id, accion, detalle, por) SELECT up.id, 'borrar', nullif(cfg.p->>'nota', ''), cfg.por FROM up, cfg RETURNING id)
SELECT json_build_object('ok', EXISTS (SELECT 1 FROM up), 'msg', 'No encontré ese movimiento.', 'bit', (SELECT count(*) FROM bit)) AS r;
