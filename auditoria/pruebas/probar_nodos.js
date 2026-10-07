// Prueba los nodos Code del flujo (permisos por rol, validaciones, avisos de Telegram y fotos). Correr después de probar_todo.py.
const { pedir, foto, nodo, pg, flujo } = require('./nodos.js');
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
// ---------- avisos por Telegram (solo mandar) ----------
const code = n => nodo(n).parameters.jsCode;
const CFG = { telegram_token: '123:ABC', chat_ids: '8552803594, 360000001' };
const origen = (n, cfg = CFG) => new Function('$', '$input', code('Origen'))(x => ({ get isExecuted() { return x === n; } }), { first: () => ({ json: cfg }) })[0].json;
let o = origen('Cada hora');
ok(o.origen === 'avisos' && o.chats.join() === '8552803594,360000001', 'varios chats separados por coma', o);
ok(origen('Resumen del día').origen === 'resumen', 'resumen del día');
let e2 = ''; try { origen('Cada hora', { telegram_token: 'PEGA_AQUI', chat_ids: 'PEGA' }); } catch (e) { e2 = e.message; }
ok(/token del bot/.test(e2), 'sin token o sin chats avisa claramente');
const ORG = { first: () => ({ json: o }) };
const av = { r: { ok: true, avisos: [{ clave: 'registro:9:rojo', clase: 'registro', folio: 'R-01842', empleado: 'JUAN', concepto: 'comprar 10 block <ligero>', importe: 500, estado: 'rojo',
    motivo: 'FALTA COMPROBANTE', tipo: 'compra', pedido: 'P4509', horas: 8 },
  { clave: 'retiro:1846:rojo', clase: 'retiro', folio: 'R-01846', empleado: 'CAJERA1', concepto: 'PAGO X', importe: 150, estado: 'rojo', motivo: 'RETIRO SIN COMPROBAR', horas: 2 },
  { clave: 'registro:2:naranja', clase: 'registro', folio: 'R-01843', empleado: 'JUAN', concepto: 'arena', importe: 500, estado: 'naranja', motivo: 'Faltan comprobar 30.00', horas: 1 }] } };
const msgs = new Function('$', '$input', code('Armar avisos'))(n => ORG, { first: () => ({ json: av }) });
const t0 = msgs[0].json.text;
ok(msgs.length === 2 && msgs[0].json.chat_id === '8552803594' && msgs[1].json.chat_id === '360000001', 'un mensaje por chat', msgs.length);
ok(/⚠️ <b>Comprobación pendiente<\/b> \(3\)/.test(t0) && /🔴 <b>R-01842<\/b> · \$500 · JUAN\nPedido P4509\ncomprar 10 block &lt;ligero&gt;\nFalta: ticket \+ registro de compra en Microsip · 8 h/.test(t0), 'formato del aviso', t0);
ok(/Falta: reportarlo \+ ticket/.test(t0) && /🟠 <b>R-01843<\/b>[\s\S]*Falta: Faltan comprobar 30.00/.test(t0) && /Mis ligas/.test(t0), 'retiro sin reportar y naranja', t0);
ok(msgs[0].json.claves.length === 3, 'claves para marcar');
ok(new Function('$', '$input', code('Armar avisos'))(n => ORG, { first: () => ({ json: { r: { avisos: [] } } }) }).length === 0, 'sin avisos no manda nada');
const mq = nodo('Marcar avisados');
ok(mq.executeOnce === true && /flatMap/.test(mq.parameters.options.queryReplacement), 'marcar avisados una vez');
ok(!nodo('Mandar aviso').onError, 'si Telegram falla no se marca como avisado');
pg(mq.parameters.query.replace('$1', "'{\"retiro:1846:rojo\",\"registro:9:rojo\"}'"), []);
ok(pg("SELECT count(*) FROM mov_aviso WHERE clave IN ('retiro:1846:rojo', 'registro:9:rojo')", []).trim() === '2', 'marcar avisados en la base');
const pa = nodo('Pendientes de avisar'), oa = pg(pa.parameters.query, eval(pa.parameters.options.queryReplacement.slice(3, -2)));
ok(typeof oa === 'string' && oa.includes('"avisos"'), 'consulta de avisos', oa);
const pr = nodo('Leer resumen'), or = pg(pr.parameters.query, eval(pr.parameters.options.queryReplacement.slice(3, -2)));
const rr = JSON.parse(or.slice(or.lastIndexOf('{"ok"')).trim());
const ms = new Function('$', '$input', code('Armar resumen'))(n => ORG, { first: () => ({ json: { r: rr } }) });
ok(ms.length === 2 && /AUDITORÍA — /.test(ms[0].json.text) && /movimientos cuadrados/.test(ms[0].json.text) && /sin comprobar/.test(ms[0].json.text), 'resumen del día', ms[0].json.text);
ok(!flujo().nodes.some(n => /webhook/.test(n.type) && /tg/.test(n.parameters.path || '')), 'el bot no se conecta (no hay webhook de Telegram)');
// ver ligas
const lg = pg(nodo('Ligas').parameters.query, []).trim().split('\n').pop().split('\t');
const ligas = new Function('$', nodo('Ligas para abrir').parameters.jsCode)(n => ({ first: () => ({ json: n === 'Ligas' ? { t_aud: lg[0], t_admin: lg[1], empleados: lg[2] } : { url_n8n: 'https://ai.adhesipro.com.mx' } }) }))[0].json;
ok(ligas.auditora.endsWith('?k=kaud') && ligas['empleado JUAN'].endsWith('?k=kjuan'), 'ver ligas', ligas);
console.log(oks + ' OK, ' + fallas + ' fallas');
process.exit(fallas ? 1 : 0);
