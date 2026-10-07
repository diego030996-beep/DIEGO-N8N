-- Lo que reportó el empleado en los últimos 30 días (o todo lo suyo con problemas).
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/, /*MOV*/
SELECT json_build_object('ok', true, 'lista', (SELECT coalesce(json_agg(json_build_object('ref', ref, 'fecha', fecha, 'hora', hora, 'folio', folio,
    'concepto', concepto, 'tipo', tipo, 'importe', importe, 'comprobado', comprobado, 'estado', estado, 'motivo', motivo, 'fotos', fotos,
    'pedido', pedido, 'vence', to_char(vence, 'YYYY-MM-DD HH24:MI'), 'revision', revision)
    ORDER BY CASE estado WHEN 'rojo' THEN 0 WHEN 'naranja' THEN 1 WHEN 'pendiente' THEN 2 ELSE 3 END, fecha DESC, hora DESC), '[]')
  FROM mov WHERE clase = 'registro' AND empleado = cfg.por AND (fecha >= cfg.hoy - 30 OR estado IN ('rojo', 'naranja', 'pendiente'))))
AS r FROM cfg;
