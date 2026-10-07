-- Para el grupo de Telegram: lo que pasó la hora límite y sigue mal (🔴 o 🟠), que todavía no se avisó en ese estado.
-- Solo de los últimos 3 días (no manda historia vieja). Lo que la auditora ya marcó como inconsistencia no se repite.
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*MOV*/,
v AS (SELECT mov.*, mov.clase || ':' || mov.ref || ':' || mov.estado AS clave FROM mov, cfg
      WHERE mov.estado IN ('rojo', 'naranja') AND mov.vence < cfg.ahora AND mov.fecha >= cfg.hoy - 3 AND mov.revision IS NULL)
SELECT json_build_object('ok', true, 'avisos', (SELECT coalesce(json_agg(json_build_object('clave', clave, 'clase', clase, 'folio', folio, 'empleado', empleado,
    'concepto', concepto, 'importe', importe, 'falta', falta, 'estado', estado, 'motivo', motivo, 'pedido', pedido, 'fotos', fotos, 'compra', cm_folio, 'tipo', tipo,
    'tg_user', tg_user, 'horas', round(extract(epoch FROM cfg.ahora - vence) / 3600)) ORDER BY estado DESC, vence), '[]') FROM v WHERE clave NOT IN (SELECT clave FROM mov_aviso))) AS r FROM cfg;
