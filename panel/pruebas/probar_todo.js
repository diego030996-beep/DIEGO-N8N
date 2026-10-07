// Pruebas del panel: PIN, bloqueo, sesiones, ligas propias. Correr: node panel/pruebas/probar_todo.js
const { pedir, nodo, psql } = require('./nodos.js');
let fallas = 0, oks = 0;
const ok = (c, t, extra) => { if (c) oks++; else { fallas++; console.log('FALLA:', t, extra !== undefined ? JSON.stringify(extra).slice(0, 400) : ''); } };
psql("DROP TABLE IF EXISTS panel_pin, panel_sesion, panel_liga, panel_rotacion; DROP TABLE IF EXISTS tablero_acceso, choferes_web, mov_empleado;");
// la liga para poner PIN crea la tabla y la llave de admin
const sqlLlave = nodo('Llave de administrador').parameters.query;
const llave = psql(sqlLlave).split('\n').pop().split('|');
ok(llave[0].length === 64 && llave[1] === 'f', 'llave admin creada', llave);
const K = llave[0];
psql("INSERT INTO tablero_acceso (token, rol) VALUES ('kcompras1', 'compras'), ('kaud1', 'auditor'), ('kprod1', 'produccion'), ('kviejo', 'compras');" +
     "UPDATE tablero_acceso SET activo = false WHERE token = 'kviejo';" +
     "INSERT INTO choferes_web (token, nombre) VALUES ('kofi', '*'), ('kjuan', 'Juan'), ('kbeto', 'Alberto');" +
     "INSERT INTO mov_empleado (token, nombre) VALUES ('kemp1', 'MARIA'), ('kemp2', 'LUIS');" +
     "INSERT INTO tablero_acceso (token, rol) VALUES ('kaudita', 'auditora');");
let r = pedir({ op: 'entrar', pin: '4821' });
ok(r.ok && r.sin_pin && !r.sesion, 'sin PIN avisa', r);
ok(!pedir({ op: 'crear_pin', k: 'kcompras1', nuevo: '4821' }).ok, 'llave no admin no crea PIN');
ok(/fácil/.test(pedir({ op: 'crear_pin', k: K, nuevo: '1234' }).msg), 'PIN fácil rechazado');
ok(/fácil/.test(pedir({ op: 'crear_pin', k: K, nuevo: '0000' }).msg), 'PIN repetido rechazado');
r = pedir({ op: 'crear_pin', k: K, nuevo: '4821' });
ok(r.ok && /^[0-9a-f]{64}$/.test(r.sesion), 'crear PIN da sesión', r);
const s0 = r.sesion;
ok(psql("SELECT pin_hash <> '4821' AND length(pin_hash) = 64 FROM panel_pin") === 't', 'PIN guardado con hash');
r = pedir({ op: 'ligas', s: s0 });
ok(r.ok && r.tablero.length === 5 && !r.tablero.some(t => t.token === 'kviejo'), 'ligas: llaves activas', r);
ok(r.empleados.length === 2 && r.empleados[0].nombre === 'LUIS', 'ligas: empleados de auditoría', r.empleados);
ok(r.choferes[0].nombre === '*' && r.choferes.length === 3, 'oficina primero', r.choferes);
ok(pedir({ op: 'ligas', s: 'abc123' }).salir, 'sesión falsa → salir');
ok(pedir({ op: 'ligas' }).salir, 'sin sesión → salir');
// PIN incorrecto y bloqueo
r = pedir({ op: 'entrar', pin: '1111' }); ok(r.ok && !r.sesion && r.quedan === 4, 'PIN malo, quedan 4', r);
for (let i = 0; i < 3; i++) r = pedir({ op: 'entrar', pin: '1111' });
ok(r.quedan === 1, 'quedan 1', r);
r = pedir({ op: 'entrar', pin: '1111' }); ok(r.min === 15 && !r.sesion, 'bloqueado 15 min', r);
r = pedir({ op: 'entrar', pin: '4821' }); ok(!r.sesion && r.min > 0, 'bloqueado aunque el PIN sea bueno', r);
psql("UPDATE panel_pin SET bloqueado_hasta = now() - interval '1 minute'");
r = pedir({ op: 'entrar', pin: '1111' }); ok(r.quedan === 4 && !r.min, 'al vencer el bloqueo vuelve a contar desde 0', r);
r = pedir({ op: 'entrar', pin: '4821', recordar: true });
ok(r.sesion && psql("SELECT vence > now() + interval '29 days' FROM panel_sesion WHERE token = '" + r.sesion + "'") === 't', 'recordar 30 días', r);
const s1 = r.sesion;
ok(psql('SELECT intentos FROM panel_pin') === '0', 'entrar bien reinicia intentos');
r = pedir({ op: 'entrar', pin: '4821' });
ok(psql("SELECT vence < now() + interval '13 hours' FROM panel_sesion WHERE token = '" + r.sesion + "'") === 't', 'sin recordar 12 h');
const s2 = r.sesion;
// ligas propias
ok(/https/.test(pedir({ op: 'liga_guardar', s: s1, titulo: 'Kommo', url: 'javascript:alert(1)' }).msg), 'url peligrosa rechazada');
r = pedir({ op: 'liga_guardar', s: s1, titulo: 'Kommo', url: 'https://ejemplo.kommo.com', grupo: 'Ventas' }); ok(r.ok, 'agregar liga', r);
ok(pedir({ op: 'liga_guardar', s: 'zzz', titulo: 'X', url: 'https://x.com' }).salir, 'agregar sin sesión no deja');
ok(psql('SELECT count(*) FROM panel_liga') === '1', 'solo una liga');
const id = psql('SELECT id FROM panel_liga');
r = pedir({ op: 'liga_guardar', s: s1, id, titulo: 'Kommo CRM', url: 'https://ejemplo.kommo.com/leads', grupo: 'Ventas' }); ok(r.ok, 'editar liga', r);
r = pedir({ op: 'ligas', s: s1 }); ok(r.extra.length === 1 && r.extra[0].titulo === 'Kommo CRM' && r.extra[0].grupo === 'Ventas', 'liga editada', r.extra);
ok(pedir({ op: 'liga_borrar', s: 'zzz', id }).salir && psql('SELECT count(*) FROM panel_liga') === '1', 'borrar sin sesión no deja');
r = pedir({ op: 'liga_borrar', s: s1, id }); ok(r.ok && r.borradas === 1, 'borrar liga', r);
// cambiar PIN
ok(/actual/.test(pedir({ op: 'pin', s: s1, actual: '9999', nuevo: '5937' }).msg), 'PIN actual malo');
r = pedir({ op: 'pin', s: s1, actual: '4821', nuevo: '5937' }); ok(r.ok && r.cerradas >= 2, 'cambiar PIN cierra las demás', r);
ok(pedir({ op: 'ligas', s: s1 }).ok, 'la sesión actual sigue');
ok(pedir({ op: 'ligas', s: s2 }).salir && pedir({ op: 'ligas', s: s0 }).salir, 'las otras se cerraron');
ok(!pedir({ op: 'entrar', pin: '4821' }).sesion && pedir({ op: 'entrar', pin: '5937' }).sesion, 'PIN nuevo funciona, viejo no');
// salir
r = pedir({ op: 'salir', s: s1 }); ok(r.ok && r.cerradas === 1, 'salir', r);
ok(pedir({ op: 'ligas', s: s1 }).salir, 'después de salir pide PIN');
// sesión vencida
const s3 = pedir({ op: 'entrar', pin: '5937' }).sesion;
psql("UPDATE panel_sesion SET vence = now() - interval '1 second' WHERE token = '" + s3 + "'");
ok(pedir({ op: 'ligas', s: s3 }).salir, 'sesión vencida pide PIN');
ok(psql("SELECT count(*) FROM panel_sesion WHERE token = '" + s3 + "'") === '0', 'sesiones vencidas se limpian');
// reponer PIN olvidado con la llave admin
r = pedir({ op: 'crear_pin', k: K, nuevo: '7305' }); ok(r.ok && r.sesion, 'reponer PIN con llave', r);
ok(pedir({ op: 'entrar', pin: '7305' }).sesion, 'PIN repuesto funciona');
ok(psql(sqlLlave).split('\n').pop() === K + '|t', 'liga para poner PIN no duplica la llave admin');
// inyección
r = pedir({ op: 'entrar', pin: "1' OR '1'='1" }); ok(!r.sesion && /4 a 8/.test(r.msg), 'PIN no numérico rechazado');
ok(pedir({ op: 'nada' }).msg === 'Operación desconocida.', 'op desconocida');

// ---------- regenerar llaves ----------
// así revisan la llave los otros flujos (planeador / producción / vendedor y choferes / rutas)
const rolDe = k => psql("SELECT coalesce((SELECT rol FROM tablero_acceso WHERE token = '" + k + "' AND activo LIMIT 1), 'DENEGADO')");
const choferDe = k => psql("SELECT coalesce((SELECT nombre FROM choferes_web WHERE token = '" + k + "' AND activo LIMIT 1), 'DENEGADO')");
let S = pedir({ op: 'entrar', pin: '7305' }).sesion;
const otraS = pedir({ op: 'entrar', pin: '7305' }).sesion;
const credenciales = psql("SELECT count(*) FROM pg_tables WHERE tablename NOT IN ('tablero_acceso','choferes_web','mov_empleado','panel_pin','panel_sesion','panel_liga','panel_rotacion')");
ok(rolDe('kcompras1') === 'compras', 'llave compras abre antes');
ok(pedir({ op: 'regenerar', s: 'zzz', fuente: 'tablero', t: 'kcompras1' }).salir && rolDe('kcompras1') === 'compras', 'regenerar sin sesión no hace nada');
r = pedir({ op: 'regenerar', s: S, fuente: 'tablero', t: 'kcompras1' });
ok(r.ok && /^[0-9a-f]{64}$/.test(r.token) && r.etiqueta === 'compras', 'regenerar compras', r);
ok(rolDe('kcompras1') === 'DENEGADO', 'llave vieja de compras ya no abre');
ok(rolDe(r.token) === 'compras', 'llave nueva abre con el mismo rol');
const nuevaCompras = r.token;
ok(/ya había cambiado/.test(pedir({ op: 'regenerar', s: S, fuente: 'tablero', t: 'kcompras1' }).msg), 'regenerar llave vieja otra vez avisa');
ok(!pedir({ op: 'regenerar', s: S, fuente: 'tablero', t: 'kviejo' }).ok, 'no regenera llaves desactivadas una por una');
ok(!pedir({ op: 'regenerar', s: S, fuente: 'otra', t: 'kaud1' }).ok, 'fuente inválida');
r = pedir({ op: 'ligas', s: S });
let fila = r.tablero.find(t => t.token === nuevaCompras);
ok(fila && fila.regenerada && !r.tablero.find(t => t.token === 'kaud1').regenerada, 'fecha de regeneración solo en la regenerada', r.tablero);
ok(r.tablero.length === 5, 'mismo número de llaves (se reemplaza, no se duplica)');
// chofer y oficina
r = pedir({ op: 'regenerar', s: S, fuente: 'choferes', t: 'kjuan' }); ok(r.ok && choferDe('kjuan') === 'DENEGADO' && choferDe(r.token) === 'Juan', 'regenerar chofer', r);
r = pedir({ op: 'regenerar', s: S, fuente: 'choferes', t: 'kofi' }); ok(r.ok && choferDe('kofi') === 'DENEGADO' && choferDe(r.token) === '*', 'regenerar oficina (rutas + choferes)', r);
ok(psql("SELECT count(*) FROM choferes_web WHERE nombre = '*' AND activo") === '1', 'oficina no se duplica');
const empDe = k => psql("SELECT coalesce((SELECT nombre FROM mov_empleado WHERE token = '" + k + "' AND activo LIMIT 1), 'DENEGADO')");
r = pedir({ op: 'regenerar', s: S, fuente: 'empleados', t: 'kemp1' }); ok(r.ok && empDe('kemp1') === 'DENEGADO' && empDe(r.token) === 'MARIA', 'regenerar empleado de auditoría', r);
// la bitácora no guarda llaves en claro
ok(psql("SELECT count(*) FROM panel_rotacion WHERE token_hash IN (SELECT token FROM tablero_acceso UNION SELECT token FROM choferes_web)") === '0', 'bitácora sin llaves en claro');
// regenerar todas: pide PIN
ok(/PIN/.test(pedir({ op: 'regenerar_todas', s: S }).msg), 'todas sin PIN no deja');
const antes = psql("SELECT string_agg(token, ',' ORDER BY token) FROM (SELECT token FROM tablero_acceso UNION ALL SELECT token FROM choferes_web) x");
r = pedir({ op: 'regenerar_todas', s: S, pin: '1111' });
ok(!r.ok && /incorrecto.*4/.test(r.msg), 'todas con PIN malo cuenta intento', r);
ok(psql("SELECT string_agg(token, ',' ORDER BY token) FROM (SELECT token FROM tablero_acceso UNION ALL SELECT token FROM choferes_web) x") === antes, 'PIN malo no cambia nada');
ok(pedir({ op: 'regenerar_todas', s: 'zzz', pin: '7305' }).salir, 'todas sin sesión no deja');
const viejas = psql("SELECT string_agg(token, ',') FROM (SELECT token FROM tablero_acceso WHERE activo UNION ALL SELECT token FROM choferes_web WHERE activo UNION ALL SELECT token FROM mov_empleado WHERE activo) x").split(',');
r = pedir({ op: 'regenerar_todas', s: S, pin: '7305' });
ok(r.ok && r.llaves === 10 && r.cerradas >= 1, 'regenerar todas (incluye empleados de auditoría)', r);
ok(viejas.every(k => rolDe(k) === 'DENEGADO' && choferDe(k) === 'DENEGADO'), 'ninguna llave vieja abre');
ok(empDe('kemp2') === 'DENEGADO', 'empleado viejo ya no abre');
ok(rolDe('kviejo') === 'DENEGADO' && psql("SELECT count(*) FROM tablero_acceso WHERE token = 'kviejo'") === '0', 'también cambia las desactivadas');
ok(psql("SELECT count(*) FROM tablero_acceso WHERE activo") === '5' && psql("SELECT count(*) FROM choferes_web WHERE activo") === '3', 'mismos accesos, mismos roles');
ok(psql("SELECT bool_and(length(token) = 64 AND token ~ '^[0-9a-f]+$') AND count(DISTINCT token) = count(*) FROM (SELECT token FROM tablero_acceso UNION ALL SELECT token FROM choferes_web) x") === 't', 'llaves nuevas de 64 hex y únicas');
ok(pedir({ op: 'ligas', s: S }).ok && pedir({ op: 'ligas', s: otraS }).salir, 'sigue mi sesión, se cierran las demás');
r = pedir({ op: 'ligas', s: S });
ok(r.ultima_todas && r.tablero.every(t => t.regenerada) && r.choferes.every(c => c.regenerada) && r.empleados.every(e => e.regenerada), 'fechas de regeneración', r);
ok(psql('SELECT count(*) FROM pg_tables WHERE tablename NOT IN (\'tablero_acceso\',\'choferes_web\',\'mov_empleado\',\'panel_pin\',\'panel_sesion\',\'panel_liga\',\'panel_rotacion\')') === credenciales, 'no toca otras tablas');
const Knueva = r.tablero.find(t => t.rol === 'admin').token;
ok(!pedir({ op: 'crear_pin', k: K, nuevo: '7305' }).ok && pedir({ op: 'crear_pin', k: Knueva, nuevo: '7305' }).ok, 'liga para poner PIN usa la llave admin nueva');
// código de la liga
const res = new Function('$', nodo('Ligas para abrir').parameters.jsCode)(n => ({ first: () => ({ json: n === 'Configuración (liga)' ? { url_n8n: 'https://ai.adhesipro.com.mx/' } : { t_admin: Knueva, hay_pin: true } }) }))[0].json;
ok(res.panel === 'https://ai.adhesipro.com.mx/webhook/mis-ligas' && res.poner_pin.endsWith('?k=' + Knueva), 'ligas del nodo manual', res);
console.log(oks + ' OK, ' + fallas + ' fallas');
process.exit(fallas ? 1 : 0);
