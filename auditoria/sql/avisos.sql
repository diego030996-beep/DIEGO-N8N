-- Para Telegram: lo que ya venció y sigue en rojo, que todavía no se avisó (solo de los últimos 3 días, para no mandar historia vieja).
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*MOV*/,
v AS (SELECT mov.*, mov.clase || ':' || mov.ref AS clave FROM mov, cfg
      WHERE mov.estado = 'rojo' AND mov.vence < cfg.ahora AND mov.fecha >= cfg.hoy - 3 AND (mov.revision IS NULL OR mov.revision <> 'inconsistencia'))
SELECT json_build_object('ok', true, 'avisos', (SELECT coalesce(json_agg(json_build_object('clave', clave, 'clase', clase, 'folio', folio, 'empleado', empleado,
    'concepto', concepto, 'importe', importe, 'falta', falta, 'motivo', motivo, 'pedido', pedido, 'fotos', fotos, 'compra', cm_folio, 'tipo', tipo,
    'horas', round(extract(epoch FROM cfg.ahora - vence) / 3600)) ORDER BY vence), '[]') FROM v WHERE clave NOT IN (SELECT clave FROM mov_aviso))) AS r FROM cfg;
