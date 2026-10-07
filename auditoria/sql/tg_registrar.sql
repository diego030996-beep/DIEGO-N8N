-- Movimiento mandado desde el grupo de Telegram (foto + texto, o respuesta a un aviso).
-- p = {retiro_num, registro_id, compra_folio, importe, pedido, concepto, tipo, metodo, foto, tg_user, tg_nombre}
-- Si el retiro (o el movimiento) ya existe, solo agrega el comprobante; si no, lo crea. El importe del retiro sale de Microsip.
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*MOV*/,
who AS (SELECT coalesce((SELECT nullif(upper(trim(t.nombre)), '') FROM choferes_tg t WHERE t.chat_id = cfg.p->>'tg_user'), nullif(cfg.p->>'tg_nombre', ''), 'TELEGRAM') AS nombre FROM cfg),
r AS (SELECT ret.* FROM ret, cfg WHERE coalesce(cfg.p->>'retiro_num', '') <> ''
        AND ltrim(regexp_replace(ret.folio, '[^0-9]', '', 'g'), '0') = ltrim(cfg.p->>'retiro_num', '0') ORDER BY ret.fecha DESC LIMIT 1),
c AS (SELECT cmp.* FROM cmp, cfg WHERE coalesce(cfg.p->>'compra_folio', '') <> ''
        AND ltrim(regexp_replace(cmp.folio, '[^0-9]', '', 'g'), '0') = ltrim(regexp_replace(cfg.p->>'compra_folio', '[^0-9]', '', 'g'), '0') ORDER BY cmp.fecha DESC LIMIT 1),
g AS (SELECT r0.* FROM reg0 r0, cfg
      WHERE (EXISTS (SELECT 1 FROM r) AND r0.retiro_id = (SELECT id FROM r))
         OR (coalesce(cfg.p->>'registro_id', '') <> '' AND r0.id::text = cfg.p->>'registro_id')
         OR (EXISTS (SELECT 1 FROM c) AND r0.compra_id = (SELECT id FROM c))
      LIMIT 1),
chk AS (SELECT CASE
          WHEN coalesce(p->>'retiro_num', '') <> '' AND NOT EXISTS (SELECT 1 FROM r) THEN 'No encontré el retiro R-' || (p->>'retiro_num') || ' en Microsip (¿ya se copió? ¿está excluido?).'
          WHEN coalesce(p->>'compra_folio', '') <> '' AND NOT EXISTS (SELECT 1 FROM c) AND NOT EXISTS (SELECT 1 FROM g) THEN 'No encontré la compra ' || (p->>'compra_folio') || ' en Microsip.'
          WHEN coalesce(p->>'registro_id', '') <> '' AND NOT EXISTS (SELECT 1 FROM g) THEN 'No encontré el movimiento M-' || (p->>'registro_id') || '.'
          WHEN (SELECT revision FROM g) = 'aprobado' THEN 'Ese movimiento ya está aprobado por auditoría.'
          WHEN NOT EXISTS (SELECT 1 FROM g) AND NOT EXISTS (SELECT 1 FROM r) AND NOT EXISTS (SELECT 1 FROM c) AND coalesce(p->>'importe', '') = ''
            THEN 'Escribe el folio del retiro (ej. R-01842) o el importe junto con la foto.' END AS err FROM cfg),
ins AS (INSERT INTO mov_registro (base, fecha, hora, retiro_id, retiro_folio, metodo, tipo, concepto, proveedor, pedido, importe, empleado, compra_id, tg_user)
        SELECT cfg.base, coalesce(r.fecha, c.fecha, cfg.hoy), coalesce(nullif(r.hora, ''), to_char(cfg.ahora, 'HH24:MI')), r.id, r.folio,
               CASE WHEN r.id IS NOT NULL THEN 'efectivo' ELSE coalesce(nullif(p->>'metodo', ''), 'efectivo') END,
               CASE WHEN c.id IS NOT NULL THEN 'compra' ELSE coalesce(nullif(p->>'tipo', ''), 'compra') END,
               coalesce(nullif(p->>'concepto', ''), nullif(r.descripcion, ''), CASE WHEN c.id IS NOT NULL THEN 'Compra ' || c.folio || ' ' || c.proveedor END, 'Sin descripción'),
               c.proveedor, nullif(p->>'pedido', ''), coalesce(r.importe, c.total, (p->>'importe')::numeric), who.nombre, c.id, nullif(p->>'tg_user', '')
        FROM cfg CROSS JOIN who LEFT JOIN r ON true LEFT JOIN c ON true
        WHERE (SELECT err FROM chk) IS NULL AND NOT EXISTS (SELECT 1 FROM g) RETURNING id, importe),
up AS (UPDATE mov_registro m SET pedido = coalesce(nullif(cfg.p->>'pedido', ''), m.pedido), tg_user = coalesce(m.tg_user, nullif(cfg.p->>'tg_user', ''))
       FROM cfg WHERE m.id IN (SELECT id FROM g) AND (SELECT err FROM chk) IS NULL RETURNING m.id),
tgt AS (SELECT id, importe AS resto FROM ins UNION ALL SELECT g.id, greatest(g.importe - g.comprobado, 0) FROM g, up WHERE up.id = g.id),
comp AS (INSERT INTO mov_comprobante (registro_id, importe, tipo, foto, por)
         SELECT tgt.id, coalesce(nullif(cfg.p->>'importe', '')::numeric, nullif(tgt.resto, 0), 0), 'ticket', cfg.p->>'foto', who.nombre || ' (Telegram)'
         FROM tgt, cfg, who WHERE coalesce(cfg.p->>'foto', '') <> '' RETURNING id),
bit AS (INSERT INTO mov_bitacora (registro_id, accion, detalle, por)
        SELECT tgt.id, CASE WHEN EXISTS (SELECT 1 FROM ins) THEN 'registrar' ELSE 'actualizar' END, 'por Telegram · ' || (SELECT count(*) FROM comp) || ' comprobante(s)', who.nombre
        FROM tgt, who RETURNING id)
SELECT json_build_object('ok', (SELECT err FROM chk) IS NULL, 'msg', (SELECT err FROM chk), 'id', (SELECT id FROM tgt LIMIT 1),
  'nuevo', EXISTS (SELECT 1 FROM ins), 'fotos', (SELECT count(*) FROM comp), 'quien', (SELECT nombre FROM who), 'bit', (SELECT count(*) FROM bit)) AS r;
