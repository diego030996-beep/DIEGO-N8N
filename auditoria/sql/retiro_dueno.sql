-- Retiro que hace el dueño de la caja: lo registra él mismo en la app (con huella) y se manda un comprobante a Telegram.
-- Puede ser un retiro de Microsip (retiro_id: el importe, fecha y folio salen de Microsip) o uno que no se capturó en Microsip (importe a mano).
-- p = {accion: 'nuevo' | 'anular', retiro_id, importe, fecha, nota, id}
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/, /*MOV*/,
r AS (SELECT ret.* FROM ret, cfg WHERE ret.id = nullif(cfg.p->>'retiro_id', '')),
chk AS (SELECT CASE
          WHEN p->>'_rol' <> 'admin' THEN 'Solo el administrador registra sus retiros.'
          WHEN p->>'accion' = 'nuevo' AND coalesce(p->>'retiro_id', '') <> '' AND NOT EXISTS (SELECT 1 FROM r) THEN 'Ese retiro no está en Microsip (o no aplica).'
          WHEN p->>'accion' = 'nuevo' AND coalesce(p->>'retiro_id', '') <> ''
               AND EXISTS (SELECT 1 FROM mov_registro g WHERE g.base = cfg.base AND g.retiro_id = p->>'retiro_id' AND NOT g.borrado)
            THEN 'Ese retiro ya lo reportó el encargado como compra o gasto.'
          WHEN p->>'accion' = 'nuevo' AND coalesce(p->>'retiro_id', '') <> ''
               AND EXISTS (SELECT 1 FROM mov_retiro_dueno d WHERE d.base = cfg.base AND d.retiro_id = p->>'retiro_id' AND NOT d.anulado)
            THEN 'Ese retiro ya está registrado como tuyo.'
          WHEN p->>'accion' = 'anular' AND NOT EXISTS (SELECT 1 FROM mov_retiro_dueno d WHERE d.base = cfg.base AND d.id::text = p->>'id' AND NOT d.anulado)
            THEN 'No encontré ese retiro (o ya estaba anulado).' END AS err FROM cfg),
v AS (SELECT cfg.base, coalesce(r.fecha, nullif(cfg.p->>'fecha', '')::date, cfg.hoy) AS fecha, coalesce(nullif(r.hora, ''), to_char(cfg.ahora, 'HH24:MI')) AS hora,
             coalesce(r.importe, (cfg.p->>'importe')::numeric) AS importe, nullif(cfg.p->>'nota', '') AS nota, r.id AS retiro_id, r.folio AS retiro_folio, cfg.por, now() AS en
      FROM cfg LEFT JOIN r ON true WHERE cfg.p->>'accion' = 'nuevo' AND (SELECT err FROM chk) IS NULL),
ins AS (INSERT INTO mov_retiro_dueno (base, fecha, hora, importe, nota, retiro_id, retiro_folio, por, creado, huella)
        SELECT v.base, v.fecha, v.hora, v.importe, v.nota, v.retiro_id, v.retiro_folio, v.por, v.en,
               upper(left(encode(sha256(convert_to(concat_ws('|', v.base, v.fecha, v.hora, v.importe, v.retiro_id, v.por, v.en), 'UTF8')), 'hex'), 12))
        FROM v RETURNING *),
an AS (UPDATE mov_retiro_dueno d SET anulado = true, anulado_nota = nullif(cfg.p->>'nota', ''), anulado_en = now()
       FROM cfg WHERE cfg.p->>'accion' = 'anular' AND (SELECT err FROM chk) IS NULL AND d.base = cfg.base AND d.id::text = cfg.p->>'id' AND NOT d.anulado RETURNING d.*),
bit AS (INSERT INTO mov_bitacora (ref, accion, detalle, por)
        SELECT 'dueno:' || x.id, CASE WHEN x.anulado THEN 'anular retiro del dueño' ELSE 'retiro del dueño' END,
               x.importe || coalesce(' · ' || x.retiro_folio, '') || ' · huella ' || x.huella || coalesce(' · ' || nullif(cfg.p->>'nota', ''), ''), cfg.por
        FROM (SELECT * FROM ins UNION ALL SELECT * FROM an) x, cfg RETURNING id)
SELECT CASE WHEN (SELECT err FROM chk) IS NOT NULL THEN json_build_object('ok', false, 'msg', (SELECT err FROM chk))
  ELSE json_build_object('ok', true, 'accion', cfg.p->>'accion',
    'retiro', (SELECT row_to_json(x) FROM (SELECT * FROM ins UNION ALL SELECT * FROM an) x LIMIT 1), 'bit', (SELECT count(*) FROM bit)) END AS r
FROM cfg;
