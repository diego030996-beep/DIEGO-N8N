-- El empleado (o la auditora) completa un movimiento: más comprobantes, pedido, proveedor, concepto o tipo. No se puede si ya está aprobado.
-- p = {id, concepto?, tipo?, proveedor?, pedido?, comprobantes?: [...]}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/,
g AS (SELECT m.* FROM mov_registro m, cfg WHERE m.base = cfg.base AND m.id = (cfg.p->>'id')::bigint AND NOT m.borrado
        AND (cfg.p->>'_rol' IN ('admin', 'auditora') OR m.empleado = cfg.por)),
chk AS (SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM g) THEN 'No encontré ese movimiento (o no es tuyo).'
                    WHEN (SELECT revision FROM g) = 'aprobado' THEN 'Ya está aprobado por auditoría; pide que lo reabran para cambiarlo.' END AS err),
up AS (UPDATE mov_registro m SET concepto = coalesce(nullif(p->>'concepto', ''), m.concepto), tipo = coalesce(nullif(p->>'tipo', ''), m.tipo),
              proveedor = CASE WHEN p ? 'proveedor' THEN nullif(p->>'proveedor', '') ELSE m.proveedor END,
              pedido = CASE WHEN p ? 'pedido' THEN nullif(p->>'pedido', '') ELSE m.pedido END,
              revision = CASE WHEN m.revision = 'inconsistencia' THEN m.revision ELSE NULL END
       FROM cfg WHERE m.id IN (SELECT id FROM g) AND (SELECT err FROM chk) IS NULL RETURNING m.id),
comp AS (INSERT INTO mov_comprobante (registro_id, importe, tipo, foto, por)
         SELECT up.id, (x->>'importe')::numeric, x->>'tipo', x->>'foto', cfg.por FROM up, cfg, jsonb_array_elements(coalesce(cfg.p->'comprobantes', '[]')) x RETURNING id),
bit AS (INSERT INTO mov_bitacora (registro_id, accion, detalle, por)
        SELECT up.id, 'actualizar', concat_ws(' · ', CASE WHEN (SELECT count(*) FROM comp) > 0 THEN '+' || (SELECT count(*) FROM comp) || ' comprobante(s)' END,
               CASE WHEN p ? 'pedido' THEN 'pedido ' || coalesce(nullif(p->>'pedido', ''), '(quitado)') END), cfg.por FROM up, cfg RETURNING id)
SELECT json_build_object('ok', (SELECT err FROM chk) IS NULL, 'msg', (SELECT err FROM chk), 'fotos', (SELECT count(*) FROM comp), 'bit', (SELECT count(*) FROM bit)) AS r;
