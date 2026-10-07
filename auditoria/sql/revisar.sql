-- La auditora decide: aprobar, marcar inconsistencia o reabrir. p = {id, accion, nota}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/,
up AS (UPDATE mov_registro m SET revision = CASE p->>'accion' WHEN 'aprobar' THEN 'aprobado' WHEN 'inconsistencia' THEN 'inconsistencia' END,
              revision_nota = nullif(p->>'nota', ''), revisado_por = CASE WHEN p->>'accion' = 'reabrir' THEN NULL ELSE cfg.por END,
              revisado_en = CASE WHEN p->>'accion' = 'reabrir' THEN NULL ELSE now() END
       FROM cfg WHERE m.base = cfg.base AND m.id = (p->>'id')::bigint AND NOT m.borrado RETURNING m.id),
bit AS (INSERT INTO mov_bitacora (registro_id, accion, detalle, por) SELECT up.id, cfg.p->>'accion', nullif(cfg.p->>'nota', ''), cfg.por FROM up, cfg RETURNING id)
SELECT json_build_object('ok', EXISTS (SELECT 1 FROM up), 'msg', 'No encontré ese movimiento.', 'bit', (SELECT count(*) FROM bit)) AS r;
