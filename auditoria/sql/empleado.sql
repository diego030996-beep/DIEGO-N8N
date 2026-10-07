-- Alta de empleado con su liga, o activar/desactivar. p = {nombre} | {token, activo}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/,
ins AS (INSERT INTO mov_empleado (token, nombre) SELECT replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), p->>'nombre'
        FROM cfg WHERE coalesce(p->>'nombre', '') <> '' AND NOT EXISTS (SELECT 1 FROM mov_empleado e WHERE upper(e.nombre) = upper(cfg.p->>'nombre') AND e.activo)
        RETURNING token),
up AS (UPDATE mov_empleado e SET activo = (p->>'activo') = 'si' FROM cfg WHERE coalesce(p->>'token', '') <> '' AND e.token = p->>'token' RETURNING e.token)
SELECT json_build_object('ok', EXISTS (SELECT 1 FROM ins) OR EXISTS (SELECT 1 FROM up),
  'msg', CASE WHEN coalesce(p->>'nombre', '') <> '' THEN 'Ya hay un empleado activo con ese nombre.' ELSE 'No encontré ese empleado.' END,
  'token', (SELECT token FROM ins)) AS r FROM cfg;
