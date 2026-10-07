-- Tablero de la auditora: resumen del periodo + lista (solo problemas o todo). Los problemas abiertos de días anteriores siempre se muestran.
-- p = {desde, hasta, ver: 'problemas' | 'todo'}
SET LOCAL statement_timeout = '25s';
WITH /*CTX*/, /*MOV*/,
rg AS (SELECT coalesce(nullif(p->>'desde', '')::date, hoy) AS d1, coalesce(nullif(p->>'hasta', '')::date, hoy) AS d2, coalesce(p->>'ver', 'problemas') AS ver FROM cfg),
m AS (SELECT mov.*, mov.fecha < rg.d1 AS atrasado,
             CASE mov.estado WHEN 'rojo' THEN 0 WHEN 'naranja' THEN 1 WHEN 'pendiente' THEN 2 ELSE 3 END AS pri
      FROM mov, rg WHERE mov.fecha BETWEEN rg.d1 AND rg.d2 OR (mov.fecha < rg.d1 AND mov.estado IN ('rojo', 'naranja'))),
dentro AS (SELECT m.* FROM m WHERE NOT atrasado),
lista AS (SELECT m.* FROM m, rg WHERE rg.ver = 'todo' OR m.estado <> 'verde' ORDER BY m.pri, m.vence, m.fecha, m.hora LIMIT 400)
SELECT json_build_object('ok', true, 'desde', rg.d1, 'hasta', rg.d2, 'ahora', to_char(cfg.ahora, 'YYYY-MM-DD HH24:MI'),
  'resumen', (SELECT json_build_object('verde', count(*) FILTER (WHERE estado = 'verde'), 'naranja', count(*) FILTER (WHERE estado = 'naranja'),
                'rojo', count(*) FILTER (WHERE estado = 'rojo'), 'pendiente', count(*) FILTER (WHERE estado = 'pendiente'),
                'total', coalesce(sum(importe), 0), 'sin_comprobar', coalesce(sum(greatest(falta, 0)) FILTER (WHERE estado <> 'verde'), 0)) FROM dentro),
  'atrasados', (SELECT json_build_object('n', count(*), 'monto', coalesce(sum(greatest(falta, 0)), 0)) FROM m WHERE atrasado),
  'por_empleado', (SELECT coalesce(json_agg(x ORDER BY x.problemas DESC, x.nombre), '[]') FROM (
       SELECT coalesce(nullif(empleado, ''), '(sin nombre)') AS nombre, count(*) AS n, count(*) FILTER (WHERE estado IN ('rojo', 'naranja')) AS problemas,
              coalesce(sum(greatest(falta, 0)) FILTER (WHERE estado <> 'verde'), 0) AS sin_comprobar
       FROM dentro WHERE clase = 'registro' GROUP BY 1) x),
  'lista', (SELECT coalesce(json_agg(json_build_object('clase', clase, 'ref', ref, 'fecha', fecha, 'hora', hora, 'folio', folio, 'empleado', empleado,
              'concepto', concepto, 'tipo', tipo, 'metodo', metodo, 'importe', importe, 'comprobado', comprobado, 'falta', falta, 'estado', estado,
              'motivo', motivo, 'vence', to_char(vence, 'YYYY-MM-DD HH24:MI'), 'horas', round(extract(epoch FROM cfg.ahora - vence) / 3600, 1),
              'fotos', fotos, 'pedido', pedido, 'compra', cm_folio, 'proveedor', cm_proveedor, 'atrasado', atrasado)), '[]') FROM lista)
) AS r FROM cfg, rg;
