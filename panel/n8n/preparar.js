// Panel general: revisa lo que pide la página y arma la consulta. Toda operación (menos entrar / crear PIN) exige una sesión vigente.
const ESQUEMA = __ESQUEMA__;
const SES = "EXISTS (SELECT 1 FROM panel_sesion WHERE token = $1 AND vence > now())";
const HASH = (sal, pin) => "encode(sha256(convert_to(" + sal + " || ':' || " + pin + ", 'UTF8')), 'hex')";
const NUEVA = "replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')";
const SQL = {
  // $1 = PIN, $2 = 'si' para recordar 30 días. 5 intentos fallidos = 15 min bloqueado.
  entrar: `WITH p AS (SELECT * FROM panel_pin WHERE id = 1 FOR UPDATE),
v AS (SELECT (p.bloqueado_hasta IS NOT NULL AND p.bloqueado_hasta > now()) AS trabado, p.pin_hash = ${HASH('p.pin_sal', '$1')} AS bien,
             CASE WHEN p.bloqueado_hasta IS NOT NULL THEN 0 ELSE p.intentos END AS base FROM p),
u AS (UPDATE panel_pin t SET
        intentos = CASE WHEN v.trabado THEN t.intentos WHEN v.bien THEN 0 ELSE v.base + 1 END,
        bloqueado_hasta = CASE WHEN v.trabado THEN t.bloqueado_hasta WHEN v.bien THEN NULL WHEN v.base + 1 >= 5 THEN now() + interval '15 minutes' ELSE NULL END
      FROM v WHERE t.id = 1 RETURNING t.intentos, t.bloqueado_hasta),
s AS (INSERT INTO panel_sesion (token, vence) SELECT ${NUEVA}, now() + CASE WHEN $2 = 'si' THEN interval '30 days' ELSE interval '12 hours' END
      FROM v WHERE v.bien AND NOT v.trabado RETURNING token)
SELECT json_build_object('ok', true, 'sin_pin', NOT EXISTS (SELECT 1 FROM v), 'sesion', (SELECT token FROM s),
  'quedan', (SELECT greatest(0, 5 - intentos) FROM u WHERE bloqueado_hasta IS NULL),
  'min', (SELECT ceil(extract(epoch FROM bloqueado_hasta - now()) / 60)::int FROM u WHERE bloqueado_hasta > now())) AS r;`,
  // $1 = llave de administrador del tablero, $2 = PIN nuevo. Sirve para crear el PIN o para reponerlo si se olvidó.
  crear_pin: `WITH a AS (SELECT 1 FROM tablero_acceso WHERE token = $1 AND rol = 'admin' AND activo LIMIT 1),
n AS (SELECT replace(gen_random_uuid()::text, '-', '') AS sal FROM a),
g AS (INSERT INTO panel_pin (id, pin_sal, pin_hash) SELECT 1, n.sal, ${HASH('n.sal', '$2')} FROM n
      ON CONFLICT (id) DO UPDATE SET pin_sal = EXCLUDED.pin_sal, pin_hash = EXCLUDED.pin_hash, intentos = 0, bloqueado_hasta = NULL, cambiado = now() RETURNING 1),
d AS (DELETE FROM panel_sesion WHERE EXISTS (SELECT 1 FROM g) RETURNING 1),
s AS (INSERT INTO panel_sesion (token, vence) SELECT ${NUEVA}, now() + interval '12 hours' FROM g RETURNING token)
SELECT CASE WHEN EXISTS (SELECT 1 FROM a) THEN json_build_object('ok', true, 'sesion', (SELECT token FROM s), 'cerradas', (SELECT count(*) FROM d))
  ELSE json_build_object('ok', false, 'msg', 'Esa llave no es de administrador. Usa la liga del nodo "Mi liga para poner PIN".') END AS r;`,
  ligas: `SELECT CASE WHEN ${SES} THEN json_build_object('ok', true,
  'tablero', COALESCE((SELECT json_agg(json_build_object('rol', rol, 'token', token) ORDER BY rol, creado) FROM tablero_acceso WHERE activo), '[]'),
  'choferes', COALESCE((SELECT json_agg(json_build_object('nombre', nombre, 'token', token) ORDER BY nombre <> '*', nombre) FROM choferes_web WHERE activo), '[]'),
  'extra', COALESCE((SELECT json_agg(json_build_object('id', id, 'titulo', titulo, 'url', url, 'grupo', grupo) ORDER BY grupo, titulo) FROM panel_liga), '[]'),
  'pin_cambiado', (SELECT cambiado FROM panel_pin WHERE id = 1),
  'sesiones', (SELECT count(*) FROM panel_sesion WHERE vence > now()))
  ELSE json_build_object('ok', false, 'salir', true, 'msg', 'Tu sesión terminó. Escribe tu PIN otra vez.') END AS r;`,
  salir: `WITH d AS (DELETE FROM panel_sesion WHERE token = $1 OR ($2 = 'todas' AND ${SES}) RETURNING 1)
SELECT json_build_object('ok', true, 'cerradas', (SELECT count(*) FROM d)) AS r;`,
  // $1 sesión, $2 PIN actual, $3 PIN nuevo. Cierra las demás sesiones.
  pin: `WITH v AS (SELECT p.pin_hash = ${HASH('p.pin_sal', '$2')} AS bien FROM panel_pin p WHERE p.id = 1 AND ${SES}),
n AS (SELECT replace(gen_random_uuid()::text, '-', '') AS sal FROM v WHERE v.bien),
u AS (UPDATE panel_pin t SET pin_sal = n.sal, pin_hash = ${HASH('n.sal', '$3')}, intentos = 0, bloqueado_hasta = NULL, cambiado = now() FROM n WHERE t.id = 1 RETURNING 1),
d AS (DELETE FROM panel_sesion WHERE token <> $1 AND EXISTS (SELECT 1 FROM u) RETURNING 1)
SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM v) THEN json_build_object('ok', false, 'salir', true, 'msg', 'Tu sesión terminó. Escribe tu PIN otra vez.')
  WHEN EXISTS (SELECT 1 FROM u) THEN json_build_object('ok', true, 'cerradas', (SELECT count(*) FROM d))
  ELSE json_build_object('ok', false, 'msg', 'El PIN actual no es correcto.') END AS r;`,
  // $1 sesión, $2 título, $3 url, $4 grupo, $5 id (para editar)
  liga_guardar: `WITH i AS (INSERT INTO panel_liga (titulo, url, grupo) SELECT $2, $3, $4 WHERE ${SES} AND $5 = '' RETURNING id),
u AS (UPDATE panel_liga SET titulo = $2, url = $3, grupo = $4 WHERE $5 <> '' AND id::text = $5 AND ${SES} RETURNING id)
SELECT CASE WHEN ${SES} THEN json_build_object('ok', EXISTS (SELECT 1 FROM i UNION ALL SELECT 1 FROM u), 'msg', 'No encontré esa liga.')
  ELSE json_build_object('ok', false, 'salir', true, 'msg', 'Tu sesión terminó. Escribe tu PIN otra vez.') END AS r;`,
  liga_borrar: `WITH d AS (DELETE FROM panel_liga WHERE id::text = $2 AND ${SES} RETURNING 1)
SELECT CASE WHEN ${SES} THEN json_build_object('ok', true, 'borradas', (SELECT count(*) FROM d))
  ELSE json_build_object('ok', false, 'salir', true, 'msg', 'Tu sesión terminó. Escribe tu PIN otra vez.') END AS r;`,
};
const fail = msg => [{ json: { ok: false, respuesta: { ok: false, msg } } }];
const b = $('API').first().json.body || {};
const op = String(b.op || '');
if (!SQL[op]) return fail('Operación desconocida.');
const txt = (v, n) => String(v ?? '').replace(/\s+/g, ' ').trim().slice(0, n);
const pinOk = v => /^\d{4,8}$/.test(String(v || ''));
const s = String(b.s || '').replace(/[^0-9a-f]/g, '').slice(0, 80);
let params;
switch (op) {
  case 'entrar': if (!pinOk(b.pin)) return fail('El PIN es de 4 a 8 números.'); params = [String(b.pin), b.recordar ? 'si' : 'no']; break;
  case 'crear_pin': {
    const k = String(b.k || '').trim().slice(0, 64);
    if (!k) return fail('Falta la llave de administrador.');
    if (!pinOk(b.nuevo)) return fail('El PIN nuevo debe ser de 4 a 8 números.');
    if (/^(\d)\1+$/.test(b.nuevo) || '0123456789'.includes(b.nuevo) || '9876543210'.includes(b.nuevo)) return fail('Ese PIN es muy fácil de adivinar; usa otro.');
    params = [k, String(b.nuevo)]; break; }
  case 'pin':
    if (!pinOk(b.actual) || !pinOk(b.nuevo)) return fail('El PIN es de 4 a 8 números.');
    if (/^(\d)\1+$/.test(b.nuevo) || '0123456789'.includes(b.nuevo) || '9876543210'.includes(b.nuevo)) return fail('Ese PIN es muy fácil de adivinar; usa otro.');
    params = [s, String(b.actual), String(b.nuevo)]; break;
  case 'ligas': params = [s]; break;
  case 'salir': params = [s, b.todas ? 'todas' : '']; break;
  case 'liga_guardar': {
    const titulo = txt(b.titulo, 80), url = String(b.url || '').trim().slice(0, 1000), grupo = txt(b.grupo, 40) || 'Otras ligas';
    if (!titulo) return fail('Ponle nombre a la liga.');
    if (!/^https?:\/\/[^\s]+$/i.test(url)) return fail('La liga debe empezar con https://');
    const id = b.id ? String(b.id) : '';
    if (id && !/^\d{1,9}$/.test(id)) return fail('Liga inválida.');
    params = [s, titulo, url, grupo, id]; break; }
  case 'liga_borrar': if (!/^\d{1,9}$/.test(String(b.id || ''))) return fail('Liga inválida.'); params = [s, String(b.id)]; break;
}
if (op !== 'entrar' && op !== 'crear_pin' && !s) return [{ json: { ok: false, respuesta: { ok: false, salir: true, msg: 'Escribe tu PIN.' } } }];
const sql = 'SET LOCAL statement_timeout = 15000;\n' + ESQUEMA + '\n' + SQL[op];
return [{ json: { ok: true, op, sql, params } }];
