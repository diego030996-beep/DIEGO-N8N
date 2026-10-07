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
// ---------- bot de auditoría en el grupo ----------
const code = n => nodo(n).parameters.jsCode;
const CFG = { telegram_token: '123:ABC', chat_id: '-100555', secreto: 's3', url_n8n: 'https://ai.adhesipro.com.mx' };
const leerMsg = (msg, headers = { 'x-telegram-bot-api-secret-token': 's3' }) => new Function('$', code('Leer mensaje'))(n => ({ first: () => ({ json: n === 'Telegram' ? { headers, body: { message: msg } } : CFG }) }));
const M = (o) => Object.assign({ message_id: 7, chat: { id: -100555, type: 'supergroup' }, from: { id: 111, first_name: 'Walter', last_name: 'Lara' } }, o);
const PH = [{ file_id: 'chico', file_size: 100 }, { file_id: 'grande', file_size: 90000 }];
let x = leerMsg(M({ photo: PH, caption: 'R-01851 $700 P4509 cemento gris' }))[0].json;
ok(x.ruta === 'foto' && x.file_id === 'grande' && x.p.retiro_num === '1851' && x.p.importe === '700' && x.p.pedido === 'P4509' && x.p.concepto === 'cemento gris' && x.p.tipo === 'compra', 'foto con folio, importe y pedido', x.p);
ok(x.p.tg_user === '111' && x.p.tg_nombre === 'WALTER LARA', 'quién la mandó');
x = leerMsg(M({ photo: PH, caption: 'gasolina 1,250.50 tarjeta nissan' }))[0].json;
ok(x.p.importe === '1250.5' && x.p.tipo === 'gasolina' && x.p.metodo === 'tarjeta' && !x.p.retiro_num, 'gasolina con tarjeta sin retiro', x.p);
x = leerMsg(M({ photo: PH, caption: '', reply_to_message: { from: { is_bot: true }, text: '🔴 R-01846 · $150 · CAJERA1\nFalta: …\nRef: retiro R-01846' } }))[0].json;
ok(x.p.retiro_num === '1846', 'respuesta con foto a un aviso de retiro', x.p);
x = leerMsg(M({ photo: PH, caption: '30', reply_to_message: { from: { is_bot: true }, text: '🟠 R-01843 …\nRef: M-2' } }))[0].json;
ok(x.p.registro_id === '2' && x.p.importe === '30', 'respuesta a un aviso de movimiento', x.p);
x = leerMsg(M({ photo: PH, reply_to_message: { from: { is_bot: true }, text: '🔴 C-8393 …\nRef: compra C-8393' } }))[0].json;
ok(x.p.compra_folio === 'C-8393', 'respuesta a un aviso de compra', x.p);
ok(leerMsg(M({ photo: PH, caption: 'ya llegué con el cliente' })).length === 0, 'foto que no es de auditoría se ignora');
ok(/De qué retiro/.test(leerMsg(M({ photo: PH, caption: 'ticket' }))[0].json.envio.text), 'foto de ticket sin datos pide el folio');
ok(leerMsg(M({ photo: PH, caption: 'R-01851 700' }), { 'x-telegram-bot-api-secret-token': 'otro' }).length === 0, 'sin la clave secreta se ignora');
ok(leerMsg(Object.assign(M({ photo: PH, caption: 'R-01851 700' }), { chat: { id: -999 } })).length === 0, 'otro grupo se ignora');
ok(leerMsg(M({ text: 'hola' })).length === 0, 'texto normal se ignora');
x = leerMsg(M({ text: '/pendientes@AuditoriaBot' }))[0].json; ok(x.ruta === 'comando' && x.que === 'pendientes', '/pendientes');
x = leerMsg(M({ text: '/folio R-01842' }))[0].json; ok(x.ruta === 'comando' && x.q === 'R-01842', '/folio');
ok(/Auditoría de movimientos/.test(leerMsg(M({ text: '/ayuda' }))[0].json.envio.text), '/ayuda');
// guardar foto real por la ruta completa (getBinaryDataBuffer simulado)
const L1 = leerMsg(M({ photo: PH, caption: 'R-01846 150 flete' }))[0].json;
const nodes2 = { 'Leer mensaje': { first: () => ({ json: L1 }) } };
const f2 = new Function('$', 'return (async function(){' + code('Foto a texto') + '}).call(this)').call({ helpers: { getBinaryDataBuffer: async () => Buffer.from(FOTO, 'base64') } }, n => nodes2[n]);
f2.then(res => {
  const q1 = res[0].json, o1 = pg(q1.sql, q1.params);
  const g1 = JSON.parse(o1.slice(o1.lastIndexOf('{"ok"')).trim());
  ok(g1.ok && g1.nuevo && g1.quien === 'WALAS', 'guardar desde Telegram (nombre del bot de choferes)', g1);
  nodes2['Pedir estado'] = { first: () => ({ json: est }) };
  const est = new Function('$', '$input', code('Pedir estado'))(n => nodes2[n], { first: () => ({ json: { r: g1 } }) })[0].json;
  const o2 = pg(est.sql, est.params);
  const d2 = JSON.parse(o2.slice(o2.lastIndexOf('{"ok"')).trim());
  const resp = new Function('$', '$input', code('Contestar foto'))(n => nodes2[n], { first: () => ({ json: { r: d2 } }) })[0].json;
  ok(/R-01846<\/b> · \$150 · WALAS/.test(resp.text) && /Ref: M-\d+/.test(resp.text) && resp.chat_id === '-100555' && resp.reply_parameters.message_id === 7, 'contesta en el grupo con el semáforo', resp.text);
  // comando /pendientes contra la base
  const C = leerMsg(M({ text: '/pendientes' }))[0].json, oc = pg(C.sql, C.params);
  const rc = JSON.parse(oc.slice(oc.lastIndexOf('{"ok"')).trim());
  const tc = new Function('$', '$input', code('Contestar comando'))(n => ({ first: () => ({ json: C }) }), { first: () => ({ json: { r: rc } }) })[0].json;
  ok(/Auditoría de hoy/.test(tc.text) && /sin comprobar/.test(tc.text), '/pendientes contesta', tc.text);
  // avisos uno por uno
  const av = { r: { ok: true, avisos: Array.from({ length: 10 }, (_, i) => ({ clave: 'registro:' + (i + 1) + ':rojo', clase: 'registro', folio: 'R-0' + (1800 + i), empleado: 'JUAN',
    concepto: 'block <ligero>', importe: 500, estado: i % 2 ? 'naranja' : 'rojo', motivo: 'COMPRA NO REGISTRADA en Microsip', pedido: 'P4509', tg_user: i === 0 ? '111' : null, horas: 2 })) } };
  const msgs = new Function('$', '$input', code('Armar avisos'))(n => ({ first: () => ({ json: CFG }) }), { first: () => ({ json: av }) });
  ok(msgs.length === 9 && msgs[8].json.claves.length === 2, '8 avisos individuales + 1 de resumen', msgs.length);
  ok(/tg:\/\/user\?id=111/.test(msgs[0].json.text) && /Ref: M-1/.test(msgs[0].json.text) && /&lt;ligero&gt;/.test(msgs[0].json.text) && /Responde a este mensaje/.test(msgs[0].json.text), 'aviso etiqueta al responsable y trae la referencia', msgs[0].json.text);
  ok(msgs[1].json.text.startsWith('🟠'), 'naranjas también se avisan');
  const mq = nodo('Marcar avisados');
  ok(mq.executeOnce === true && /flatMap/.test(mq.parameters.options.queryReplacement), 'marcar avisados una vez con todas las claves');
  ok(!nodo('Mandar aviso').onError, 'si Telegram falla, no se marca como avisado');
  // avisos y resumen con la consulta real
  const pa = nodo('Pendientes de avisar'), oa = pg(pa.parameters.query, eval(pa.parameters.options.queryReplacement.slice(3, -2)));
  ok(typeof oa === 'string' && oa.includes('"avisos"'), 'consulta de avisos', oa);
  const pr = nodo('Leer resumen'), or = pg(pr.parameters.query, eval(pr.parameters.options.queryReplacement.slice(3, -2)));
  const rr = JSON.parse(or.slice(or.lastIndexOf('{"ok"')).trim());
  const ms = new Function('$', '$input', code('Armar resumen'))(n => ({ first: () => ({ json: CFG }) }), { first: () => ({ json: { r: rr } }) })[0].json;
  ok(/Auditoría del día/.test(ms.text) && ms.chat_id === '-100555', 'resumen del día', ms.text);
  // origen y conectar
  const org = n => new Function('$', '$input', code('Origen'))(x => ({ get isExecuted() { return x === n; } }), { first: () => ({ json: CFG }) })[0].json.origen;
  ok(org('Telegram') === 'telegram' && org('Cada hora') === 'avisos' && org('Resumen del día') === 'resumen' && org('Conectar bot') === 'conectar', 'origen de cada disparador');
  let e2 = ''; try { new Function('$', '$input', code('Origen'))(x => ({ isExecuted: x === 'Cada hora' }), { first: () => ({ json: { telegram_token: 'PEGA', chat_id: 'x' } }) }); } catch (e) { e2 = e.message; }
  ok(/token del bot/.test(e2), 'sin token avisa claramente');
  const cn = new Function('$', code('Datos del bot'))(n => ({ first: () => ({ json: CFG }) }))[0].json;
  ok(cn.url === 'https://ai.adhesipro.com.mx/webhook/auditoria-mov-tg' && cn.secret_token === 's3', 'conectar webhook con clave secreta', cn);
  fin();
});
// ver ligas
const lg = pg(nodo('Ligas').parameters.query, []).trim().split('\n').pop().split('\t');
const ligas = new Function('$', nodo('Ligas para abrir').parameters.jsCode)(n => ({ first: () => ({ json: n === 'Ligas' ? { t_aud: lg[0], t_admin: lg[1], empleados: lg[2] } : { url_n8n: 'https://ai.adhesipro.com.mx' } }) }))[0].json;
ok(ligas.auditora.endsWith('?k=kaud') && ligas['empleado JUAN'].endsWith('?k=kjuan'), 'ver ligas', ligas);
function fin() {
console.log(oks + ' OK, ' + fallas + ' fallas');
process.exit(fallas ? 1 : 0);
}
