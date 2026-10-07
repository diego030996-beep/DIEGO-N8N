-- Lo que la página necesita al abrir: configuración, retiros de caja sin reportar (para escoger) y empleados (solo admin).
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/, /*MOV*/
SELECT json_build_object('ok', true, 'hoy', cfg.hoy, 'ahora', to_char(cfg.ahora, 'YYYY-MM-DD HH24:MI'), 'desde', cfg.desde,
  'cierre', to_char(cfg.cierre, 'HH24:MI'), 'tipos_compra', cfg.tipos_compra,
  'config', CASE WHEN cfg.p->>'_rol' = 'admin' THEN cfg.c END,
  'retiros', (SELECT coalesce(json_agg(json_build_object('id', r.id, 'folio', r.folio, 'fecha', r.fecha, 'hora', r.hora, 'descripcion', r.descripcion,
                'usuario', r.usuario, 'importe', r.importe) ORDER BY r.fecha DESC, r.hora DESC), '[]') FROM rsr r WHERE r.fecha >= cfg.hoy - 7),
  'empleados', CASE WHEN cfg.p->>'_rol' = 'admin' THEN (SELECT coalesce(json_agg(json_build_object('token', e.token, 'nombre', e.nombre, 'activo', e.activo) ORDER BY e.activo DESC, e.nombre), '[]') FROM mov_empleado e) END
) AS r FROM cfg;
