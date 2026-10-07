-- Nuevo movimiento con sus comprobantes. Si viene de un retiro de caja, la fecha, hora, folio e importe salen de Microsip (no se capturan).
-- p = {retiro_id, metodo, tipo, concepto, proveedor, pedido, importe, fecha, comprobantes: [{importe, tipo, foto}]}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*MOV*/,
r AS (SELECT ret.* FROM ret, cfg WHERE ret.id = nullif(cfg.p->>'retiro_id', '')),
chk AS (SELECT CASE WHEN coalesce(p->>'retiro_id', '') <> '' AND NOT EXISTS (SELECT 1 FROM r) THEN 'Ese retiro no está en Microsip o no aplica para auditoría.'
                    WHEN coalesce(p->>'retiro_id', '') <> '' AND EXISTS (SELECT 1 FROM mov_registro g WHERE g.base = cfg.base AND g.retiro_id = p->>'retiro_id' AND NOT g.borrado)
                      THEN 'Ese retiro ya lo reportaron.' END AS err FROM cfg),
ins AS (INSERT INTO mov_registro (base, fecha, hora, retiro_id, retiro_folio, metodo, tipo, concepto, proveedor, pedido, importe, empleado)
        SELECT cfg.base, coalesce(r.fecha, nullif(p->>'fecha', '')::date, cfg.hoy), coalesce(nullif(r.hora, ''), to_char(cfg.ahora, 'HH24:MI')), r.id, r.folio,
               CASE WHEN r.id IS NOT NULL THEN 'efectivo' ELSE p->>'metodo' END, p->>'tipo', p->>'concepto', nullif(p->>'proveedor', ''), nullif(p->>'pedido', ''),
               coalesce(r.importe, (p->>'importe')::numeric), cfg.por
        FROM cfg LEFT JOIN r ON true WHERE (SELECT err FROM chk) IS NULL RETURNING id),
comp AS (INSERT INTO mov_comprobante (registro_id, importe, tipo, foto, por)
         SELECT ins.id, (x->>'importe')::numeric, x->>'tipo', x->>'foto', cfg.por FROM ins, cfg, jsonb_array_elements(coalesce(cfg.p->'comprobantes', '[]')) x RETURNING id),
bit AS (INSERT INTO mov_bitacora (registro_id, accion, detalle, por)
        SELECT ins.id, 'registrar', (SELECT count(*) FROM comp) || ' comprobante(s)', cfg.por FROM ins, cfg RETURNING id)
SELECT json_build_object('ok', (SELECT err FROM chk) IS NULL, 'msg', (SELECT err FROM chk), 'id', (SELECT id FROM ins),
  'fotos', (SELECT count(*) FROM comp), 'bit', (SELECT count(*) FROM bit)) AS r;
