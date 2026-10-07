-- Corte de caja de un día: cobros por forma de pago (y si tienen comprobante), retiros (y cuáles no lo piden), retiros del dueño, efectivo y firma.
-- p = {fecha}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*MOV*/, /*CORTE*/
SELECT json_build_object('ok', true, 'fecha', f.d, 'ahora', to_char(cfg.ahora, 'YYYY-MM-DD HH24:MI'), 'cierre', to_char(cfg.cierre, 'HH24:MI'),
  'auditado', f.d >= cfg.desde, 'desde', cfg.desde,
  'puede_firmar', cfg.p->>'_rol' = 'admin' OR (cfg.p->>'_rol' = 'auditora' AND coalesce(cfg.c->>'auditora_firma', 'no') = 'si'),
  'formas', (SELECT coalesce(json_agg(x ORDER BY x.sin_comprobante DESC, x.importe DESC), '[]') FROM formas x),
  'retiros', (SELECT coalesce(json_agg(json_build_object('ref', id, 'folio', folio, 'hora', hora, 'descripcion', descripcion, 'usuario', usuario, 'importe', importe,
                'estado', estado, 'motivo', motivo, 'tipo', tipo, 'recepcion', cm_folio, 'registro_id', registro_id) ORDER BY hora), '[]') FROM rts),
  'dueno', (SELECT coalesce(json_agg(json_build_object('id', id, 'hora', hora, 'importe', importe, 'nota', nota, 'retiro_folio', retiro_folio, 'por', por) ORDER BY hora), '[]') FROM dd),
  'totales', (SELECT row_to_json(tot) FROM tot),
  'pendientes', (SELECT json_build_object('n', n, 'monto', monto) FROM pend),
  'firma', (SELECT json_build_object('esperado', k.esperado, 'entregado', k.entregado, 'diferencia', k.diferencia, 'pendientes', k.pendientes,
              'pendiente_monto', k.pendiente_monto, 'nota', k.nota, 'por', k.firmado_por, 'en', k.firmado_en, 'huella', k.huella)
            FROM mov_corte k WHERE k.base = cfg.base AND k.fecha = f.d)
) AS r FROM cfg, f;
