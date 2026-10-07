// Prueba los nodos Code del flujo (permisos por rol, validaciones, avisos de Telegram y fotos). Correr después de probar_todo.py.
const { pedir, foto, nodo, pg } = require('./nodos.js');
let oks = 0, fallas = 0;
const ok = (c, t, x) => { if (c) oks++; else { fallas++; console.log('FALLA:', t, x !== undefined ? JSON.stringify(x).slice(0, 400) : ''); } };
pg("INSERT INTO tablero_acceso (token, rol) VALUES ('kadmin', 'admin'), ('kaud', 'auditora'), ('kauditor', 'auditor') ON CONFLICT DO NOTHING;" +
   "INSERT INTO mov_empleado (token, nombre) VALUES ('kjuan', 'JUAN'), ('kpedro', 'PEDRO') ON CONFLICT DO NOTHING;", []);
ok(/no tiene permiso/.test(pedir({ k: 'nada', op: 'datos' }).msg), 'liga desconocida');
ok(/no tiene permiso/.test(pedir({ k: 'kauditor', op: 'datos' }).msg), 'el auditor de compras no entra aquí');
let d = pedir({ k: 'kjuan', op: 'datos' });
ok(d.ok && d.rol === 'empleado' && d.yo === 'JUAN', 'empleado entra con su nombre', d);
ok(/permiso/.test(pedir({ k: 'kjuan', op: 'tablero' }).msg), 'empleado no ve el tablero');
ok(/permiso/.test(pedir({ k: 'kjuan', op: 'revisar', id: 1, accion: 'aprobar' }).msg), 'empleado no aprueba');
ok(/permiso/.test(pedir({ k: 'kaud', op: 'config', general: {} }).msg), 'auditora no cambia ajustes');
ok(/permiso/.test(pedir({ k: 'kaud', op: 'empleado', nombre: 'X' }).msg), 'auditora no da de alta empleados');
ok(/desconocida/.test(pedir({ k: 'kadmin', op: 'avisos' }).msg), 'avisos no se puede pedir desde la página');
d = pedir({ k: 'kadmin', op: 'datos' });
ok(d.ok && d.rol === 'admin' && Array.isArray(d.empleados) && d.config, 'admin ve empleados y ajustes');
ok(/motivo/.test(pedir({ k: 'kjuan', op: 'registrar', retiro_id: '1847', tipo: 'compra', concepto: '' }).msg), 'motivo obligatorio');
ok(/foto/.test(pedir({ k: 'kjuan', op: 'registrar', retiro_id: '1847', tipo: 'compra', concepto: 'algo', comprobantes: [{ importe: 10, foto: 'abc' }] }).msg), 'foto inválida');
ok(/importe/.test(pedir({ k: 'kjuan', op: 'registrar', metodo: 'tarjeta', tipo: 'gasto', concepto: 'algo' }).msg), 'sin retiro pide importe');
ok(/Hora/.test(pedir({ k: 'kadmin', op: 'config', general: { hora_cierre: '25:00' } }).msg), 'hora inválida');
ok(/regex|inválido/i.test(pedir({ k: 'kadmin', op: 'config', general: { retiros_excluir: '(' } }).msg), 'regex inválida');
const FOTO = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(300, 7)]).toString('base64');
let r = pedir({ k: 'kjuan', op: 'registrar', retiro_id: '1847', tipo: 'compra', concepto: 'compra tarde', comprobantes: [{ importe: 90, tipo: 'ticket', foto: FOTO }] });
ok(r.ok && r.id, 'registrar por la API', r);
ok(/ya lo reportaron/.test(pedir({ k: 'kpedro', op: 'registrar', retiro_id: '1847', tipo: 'compra', concepto: 'otra vez' }).msg), 'retiro repetido');
const cid = pg(`SELECT id FROM mov_comprobante WHERE registro_id = ${r.id}`, []).trim();
ok(!foto('kjuan', cid).json.falta && foto('kjuan', cid).binary.data.data === FOTO, 'el empleado ve su foto');
ok(!foto('kaud', cid).json.falta, 'la auditora ve la foto');
ok(foto('kpedro', cid).json.falta, 'otro empleado no ve la foto');
ok(foto('', cid).json.falta && foto('kjuan', 'x').json.falta, 'sin llave o id inválido');
ok(!pedir({ k: 'kpedro', op: 'detalle', clase: 'registro', ref: String(r.id) }).ok, 'otro empleado no abre el expediente');
// avisos de Telegram
const cfgAvisos = { telegram_token: '123:ABC', chat_id: '-100', url_n8n: 'https://ai.adhesipro.com.mx' };
const av = { r: { ok: true, avisos: [{ clave: 'retiro:1846', clase: 'retiro', folio: 'R-01846', empleado: 'CAJERA1', concepto: 'PAGO X', importe: 150, motivo: 'RETIRO SIN COMPROBAR', horas: 8 },
  { clave: 'registro:9', clase: 'registro', folio: 'R-01842', empleado: 'JUAN', concepto: 'comprar 10 block <ligero>', importe: 500, motivo: 'COMPRA NO REGISTRADA en Microsip', pedido: 'P4509', horas: 2 }] } };
const msg = new Function('$', '$input', nodo('Armar aviso').parameters.jsCode)(n => ({ first: () => ({ json: cfgAvisos }) }), { first: () => ({ json: av }) });
ok(msg.length === 1 && /R-01842<\/b> · \$500 · JUAN\nPedido P4509/.test(msg[0].json.text) && /Falta: registro de compra en Microsip · 2 h/.test(msg[0].json.text), 'mensaje de Telegram', msg[0] && msg[0].json.text);
ok(/&lt;ligero&gt;/.test(msg[0].json.text) && msg[0].json.claves.length === 2, 'mensaje escapado y con claves');
ok(new Function('$', '$input', nodo('Armar aviso').parameters.jsCode)(n => ({ first: () => ({ json: cfgAvisos }) }), { first: () => ({ json: { r: { avisos: [] } } }) }).length === 0, 'sin avisos no manda nada');
let err = ''; try { new Function('$', '$input', nodo('Armar aviso').parameters.jsCode)(n => ({ first: () => ({ json: { telegram_token: 'PEGA_AQUI', chat_id: '' } }) }), { first: () => ({ json: av }) }); } catch (e) { err = e.message; }
ok(/token del bot/.test(err), 'sin token avisa claramente');
const marca = nodo('Marcar avisados').parameters.options.queryReplacement;
ok(/claves\.map/.test(marca), 'marcar avisados usa las claves');
pg(nodo('Marcar avisados').parameters.query.replace('$1', "'{\"retiro:1846\",\"registro:9\"}'"), []);
ok(pg("SELECT count(*) FROM mov_aviso WHERE clave IN ('retiro:1846', 'registro:9')", []).trim() === '2', 'marcar avisados en la base');
// la consulta de avisos del nodo programado corre
const q = nodo('Pendientes de avisar');
const params = JSON.parse(JSON.stringify(eval(q.parameters.options.queryReplacement.slice(3, -2))));
const out = pg(q.parameters.query, params);
ok(typeof out === 'string' && out.includes('"avisos"'), 'consulta de avisos', out);
// ver ligas
const lg = pg(nodo('Ligas').parameters.query, []).trim().split('\n').pop().split('\t');
const ligas = new Function('$', nodo('Ligas para abrir').parameters.jsCode)(n => ({ first: () => ({ json: n === 'Ligas' ? { t_aud: lg[0], t_admin: lg[1], empleados: lg[2] } : { url_n8n: 'https://ai.adhesipro.com.mx' } }) }))[0].json;
ok(ligas.auditora.endsWith('?k=kaud') && ligas['empleado JUAN'].endsWith('?k=kjuan'), 'ver ligas', ligas);
console.log(oks + ' OK, ' + fallas + ' fallas');
process.exit(fallas ? 1 : 0);
