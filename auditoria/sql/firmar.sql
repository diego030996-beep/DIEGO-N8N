-- Firma el corte de caja del día (reemplaza la libreta). El efectivo esperado y lo pendiente se calculan aquí mismo (no se confía en la página).
-- Firma el administrador; la auditora solo si el administrador la autorizó en Ajustes. Deja una huella para el comprobante.
-- p = {fecha, entregado, nota}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*MOV*/, /*CORTE*/,
chk AS (SELECT CASE WHEN cfg.p->>'_rol' = 'auditora' AND coalesce(cfg.c->>'auditora_firma', 'no') <> 'si' THEN 'Solo el administrador puede firmar el corte (o la auditora, si él la autoriza en Ajustes).'
                    WHEN cfg.p->>'_rol' NOT IN ('admin', 'auditora') THEN 'Tu liga no puede firmar el corte.' END AS err FROM cfg),
v AS (SELECT f.d, tot.efectivo_neto AS esperado, (cfg.p->>'entregado')::numeric AS entregado, pend.n, pend.monto, now() AS en,
             cfg.base, cfg.por, nullif(cfg.p->>'nota', '') AS nota
      FROM f, tot, pend, cfg WHERE (SELECT err FROM chk) IS NULL),
up AS (INSERT INTO mov_corte (base, fecha, esperado, entregado, diferencia, pendientes, pendiente_monto, nota, firmado_por, firmado_en, huella)
       SELECT v.base, v.d, v.esperado, v.entregado, v.entregado - v.esperado, v.n, v.monto, v.nota, v.por, v.en,
              upper(left(encode(sha256(convert_to(concat_ws('|', v.base, v.d, v.esperado, v.entregado, v.n, v.monto, v.por, v.en), 'UTF8')), 'hex'), 12))
       FROM v
       ON CONFLICT (base, fecha) DO UPDATE SET esperado = EXCLUDED.esperado, entregado = EXCLUDED.entregado, diferencia = EXCLUDED.diferencia,
         pendientes = EXCLUDED.pendientes, pendiente_monto = EXCLUDED.pendiente_monto, nota = EXCLUDED.nota, firmado_por = EXCLUDED.firmado_por,
         firmado_en = EXCLUDED.firmado_en, huella = EXCLUDED.huella
       RETURNING *),
bit AS (INSERT INTO mov_bitacora (ref, accion, detalle, por)
        SELECT 'corte:' || up.fecha, 'firmar corte', 'esperado ' || up.esperado || ' · entregado ' || up.entregado || ' · diferencia ' || up.diferencia || ' · huella ' || up.huella, up.firmado_por
        FROM up RETURNING id)
SELECT CASE WHEN (SELECT err FROM chk) IS NOT NULL THEN json_build_object('ok', false, 'msg', (SELECT err FROM chk))
  ELSE json_build_object('ok', true, 'fecha', (SELECT fecha FROM up), 'esperado', (SELECT esperado FROM up), 'entregado', (SELECT entregado FROM up),
    'diferencia', (SELECT diferencia FROM up), 'pendientes', (SELECT pendientes FROM up), 'pendiente_monto', (SELECT pendiente_monto FROM up),
    'nota', (SELECT nota FROM up), 'por', (SELECT firmado_por FROM up), 'en', (SELECT firmado_en FROM up), 'huella', (SELECT huella FROM up),
    'totales', (SELECT row_to_json(tot) FROM tot),
    'formas', (SELECT coalesce(json_agg(json_build_object('forma', forma, 'importe', importe, 'faltan', faltan, 'sin_comprobante', sin_comprobante) ORDER BY importe DESC), '[]') FROM formas),
    'bit', (SELECT count(*) FROM bit)) END AS r;
