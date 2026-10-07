// Auditoría de movimientos: revisa lo que pide la página, aplica los permisos del rol y arma UNA consulta para Postgres.
const SQL = __SQL__;
const DEF = __DEF__;
const fail = msg => [{ json: { ok: false, respuesta: { ok: false, msg } } }];
const acc = $('Acceso').first().json;
const rol = String(acc.rol || ''), nombre = String(acc.nombre || '');
if (!rol) return fail('Esta liga no tiene permiso. Pide tu liga al administrador.');
const b = $('API').first().json.body || {};
const op = String(b.op || '');
if (!SQL[op] || op === 'avisos') return fail('Operación desconocida.');
const PERMISO = {
  // el encargado solo carga lo de auditoría: no ve el corte de caja
  empleado: ['datos', 'mis', 'registrar', 'actualizar', 'detalle', 'buscar'],
  // la auditora firma el corte solo si el administrador la autoriza (se revisa en la consulta)
  auditora: ['datos', 'mis', 'registrar', 'actualizar', 'detalle', 'buscar', 'corte', 'tablero', 'revisar', 'vincular', 'ignorar', 'firmar', 'retiros_mes', 'pedidos', 'retiros_dueno'],
  // la directora solo consulta
  directora: ['datos', 'tablero', 'corte', 'detalle', 'buscar', 'pedidos', 'retiros_mes', 'retiros_dueno'],
  admin: Object.keys(SQL),
};
if (!(PERMISO[rol] || []).includes(op)) return fail('Tu liga no tiene permiso para esto.');
const por = rol === 'empleado' ? nombre : { auditora: 'Auditora', directora: 'Directora' }[rol] || 'Administrador';
const txt = (v, n) => String(v ?? '').replace(/\s+/g, ' ').trim().slice(0, n);
const fechaOk = v => /^\d{4}-\d{2}-\d{2}$/.test(String(v || '')) && String(v) >= '2020-01-01';
const idOk = v => /^\d{1,15}$/.test(String(v ?? ''));
const refOk = v => /^[0-9A-Za-z_\-:]{1,40}$/.test(String(v ?? ''));
const montoOk = v => v !== '' && v != null && isFinite(Number(v)) && Number(v) > 0 && Number(v) <= 5e6;
const METODOS = ['efectivo', 'tarjeta', 'transferencia'];
const TIPOS = ['compra', 'gasto', 'gasolina', 'deposito', 'otro'];
const TCOMP = ['ticket', 'factura', 'transferencia', 'voucher', 'mercado pago', 'ticket firmado', 'otro'];
function comprobantes(L, obligatorio) {
  L = Array.isArray(L) ? L : [];
  if (obligatorio && !L.length) return 'Falta la foto del comprobante.';
  if (L.length > 6) return 'Máximo 6 comprobantes por movimiento.';
  for (const c of L) {
    if (!montoOk(c.importe)) return 'Pon el importe de cada comprobante.';
    if (!/^[A-Za-z0-9+/=]{200,}$/.test(String(c.foto || ''))) return 'Una foto no se pudo leer; tómala otra vez.';
    if (String(c.foto).length > 2800000) return 'Una foto es demasiado grande.';
  }
  return L.map(c => ({ importe: String(Math.round(Number(c.importe) * 100) / 100), tipo: TCOMP.includes(c.tipo) ? c.tipo : 'ticket', foto: String(c.foto) }));
}
let p = {};
switch (op) {
  case 'datos': case 'mis': break;
  case 'tablero':
    if ((b.desde && !fechaOk(b.desde)) || (b.hasta && !fechaOk(b.hasta))) return fail('Fechas inválidas.');
    p = { desde: b.desde || '', hasta: b.hasta || '', ver: b.ver === 'todo' ? 'todo' : 'problemas' }; break;
  case 'registrar': {
    const retiro = b.retiro_id ? String(b.retiro_id) : '', cobro = b.cobro_id ? String(b.cobro_id) : '';
    if (retiro && !refOk(retiro)) return fail('Retiro inválido.');
    if (cobro) {   // cobro con tarjeta / transferencia / Mercado Pago: todo sale de Microsip, solo se sube el comprobante
      if (!/^\d{1,15}:\d{1,15}$/.test(cobro)) return fail('Cobro inválido.');
      const L = comprobantes(b.comprobantes, false);
      if (typeof L === 'string') return fail(L);
      p = { cobro_id: cobro, comprobantes: L };
      break;
    }
    if (!TIPOS.includes(b.tipo)) return fail('Escoge para qué fue el dinero.');
    if (!retiro && !METODOS.includes(b.metodo)) return fail('Escoge cómo se pagó.');
    if (!retiro && !montoOk(b.importe)) return fail('Escribe el importe.');
    if (b.fecha && !fechaOk(b.fecha)) return fail('Fecha inválida.');
    const concepto = txt(b.concepto, 200);
    if (concepto.length < 3) return fail('Escribe el motivo (qué se compró o pagó).');
    const L = comprobantes(b.comprobantes, false);
    if (typeof L === 'string') return fail(L);
    p = { retiro_id: retiro, metodo: b.metodo || 'efectivo', tipo: b.tipo, concepto, proveedor: txt(b.proveedor, 80), pedido: txt(b.pedido, 30),
          importe: retiro ? '' : String(Math.round(Number(b.importe) * 100) / 100), fecha: b.fecha || '', comprobantes: L };
    break; }
  case 'actualizar': {
    if (!idOk(b.id)) return fail('Movimiento inválido.');
    const L = comprobantes(b.comprobantes, false);
    if (typeof L === 'string') return fail(L);
    p = { id: String(b.id), comprobantes: L };
    if ('pedido' in b) p.pedido = txt(b.pedido, 30);
    if ('proveedor' in b) p.proveedor = txt(b.proveedor, 80);
    if (b.concepto) p.concepto = txt(b.concepto, 200);
    if (b.tipo) { if (!TIPOS.includes(b.tipo)) return fail('Tipo inválido.'); p.tipo = b.tipo; }
    break; }
  case 'detalle':
    if (!['registro', 'retiro', 'compra', 'cobro'].includes(b.clase) || !refOk(b.ref)) return fail('Movimiento inválido.');
    p = { clase: b.clase, ref: String(b.ref) }; break;
  case 'revisar':
    if (!idOk(b.id) || !['aprobar', 'inconsistencia', 'reabrir'].includes(b.accion)) return fail('Acción inválida.');
    if (b.accion === 'inconsistencia' && txt(b.nota, 300).length < 3) return fail('Escribe qué está mal.');
    p = { id: String(b.id), accion: b.accion, nota: txt(b.nota, 300) }; break;
  case 'vincular':
    if (!idOk(b.id) || (b.compra_id && !refOk(b.compra_id))) return fail('Datos inválidos.');
    p = { id: String(b.id), compra_id: b.compra_id ? String(b.compra_id) : '' }; break;
  case 'ignorar':
    if (!['retiro', 'compra', 'cobro'].includes(b.tipo) || !refOk(b.ref)) return fail('Datos inválidos.');
    if (!b.quitar && txt(b.motivo, 200).length < 3) return fail('Escribe por qué no requiere comprobación.');
    p = { tipo: b.tipo, ref: String(b.ref), motivo: txt(b.motivo, 200), quitar: b.quitar ? 'si' : '' }; break;
  case 'buscar': p = { q: txt(b.q, 40) }; if (p.q.length < 2) return fail('Escribe al menos 2 letras o números.'); break;
  case 'empleado':
    if (b.token) { if (!/^[0-9a-f]{20,80}$/.test(String(b.token))) return fail('Empleado inválido.'); p = { token: String(b.token), activo: b.activo ? 'si' : 'no' }; }
    else { p = { nombre: txt(b.nombre, 40).toUpperCase() }; if (p.nombre.length < 2) return fail('Escribe el nombre.'); }
    break;
  case 'config': {
    const g = b.general || {}, OK = { hora_cierre: 5, tolerancia: 8, dias_compra: 3, margen_compra: 5, tipos_compra: 80, retiros_excluir: 200, retiros_gasto: 300, foto_obligatoria: 300, formas_comprobante: 200, formas_sin_comprobante: 200, compras_sin_comprobante: 10, proveedores_mostrador: 300, desde: 10, auditora_firma: 2 }, general = {};
    for (const [k, v] of Object.entries(g)) { if (!(k in OK)) return fail('Ajuste desconocido: ' + k); general[k] = txt(v, OK[k]); }
    if (general.hora_cierre && !/^([01]?\d|2[0-3]):[0-5]\d$/.test(general.hora_cierre)) return fail('Hora de cierre inválida (ej. 20:00).');
    if (general.tolerancia && !(Number(general.tolerancia) >= 0 && Number(general.tolerancia) <= 1000)) return fail('Tolerancia inválida.');
    if (general.dias_compra && !(Number.isInteger(Number(general.dias_compra)) && Number(general.dias_compra) >= 0 && Number(general.dias_compra) <= 30)) return fail('Días inválidos.');
    if (general.margen_compra && !(Number(general.margen_compra) >= 0 && Number(general.margen_compra) <= 50)) return fail('Margen inválido (0 a 50%).');
    if (general.desde && !fechaOk(general.desde)) return fail('Fecha de inicio inválida.');
    if (general.auditora_firma && !['si', 'no'].includes(general.auditora_firma)) return fail('Opción inválida.');
    if (general.compras_sin_comprobante && !['contado', 'mostrador', 'todas', 'no'].includes(general.compras_sin_comprobante)) return fail('Opción inválida.');
    if (general.tipos_compra && !general.tipos_compra.split(',').every(t => TIPOS.includes(t))) return fail('Tipos inválidos.');
    for (const k of ['retiros_excluir', 'retiros_gasto', 'foto_obligatoria', 'proveedores_mostrador', 'formas_comprobante', 'formas_sin_comprobante']) if (general[k]) { try { new RegExp(general[k], 'i'); } catch (e) { return fail('Texto inválido en ' + k + '.'); } }
    p = { general }; break; }
  case 'corte': if (b.fecha && !fechaOk(b.fecha)) return fail('Fecha inválida.'); p = { fecha: b.fecha || '' }; break;
  case 'firmar': {
    if (!fechaOk(b.fecha)) return fail('Fecha inválida.');
    const num = v => v !== '' && v != null && isFinite(Number(v)) && Math.abs(Number(v)) <= 1e8;
    if (!num(b.entregado)) return fail('Escribe el efectivo que te entregaron.');
    // lo esperado y lo pendiente se calculan en la base, no se toman de la página
    p = { fecha: b.fecha, entregado: String(Number(b.entregado)), nota: txt(b.nota, 300) };
    break; }
  case 'retiro_dueno':
    if (b.accion === 'anular') {
      if (!idOk(b.id)) return fail('Retiro inválido.');
      if (txt(b.nota, 200).length < 3) return fail('Escribe por qué se anula.');
      p = { accion: 'anular', id: String(b.id), nota: txt(b.nota, 200) };
    } else {
      const rid = b.retiro_id ? String(b.retiro_id) : '';
      if (rid && !refOk(rid)) return fail('Retiro inválido.');
      if (!rid && !montoOk(b.importe)) return fail('Escribe el importe.');
      if (b.fecha && !fechaOk(b.fecha)) return fail('Fecha inválida.');
      p = { accion: 'nuevo', retiro_id: rid, importe: rid ? '' : String(Math.round(Number(b.importe) * 100) / 100), fecha: b.fecha || '', nota: txt(b.nota, 200) };
    }
    break;
  case 'retiros_dueno':
    if ((b.desde && !fechaOk(b.desde)) || (b.hasta && !fechaOk(b.hasta))) return fail('Fechas inválidas.');
    p = { desde: b.desde || '', hasta: b.hasta || '' }; break;
  case 'retiros_mes': if (b.mes && !/^\d{4}-(0[1-9]|1[0-2])$/.test(String(b.mes))) return fail('Mes inválido.'); p = { mes: b.mes || '' }; break;
  case 'pedidos': p = { dias: Number.isInteger(Number(b.dias)) && Number(b.dias) > 0 && Number(b.dias) <= 400 ? String(Number(b.dias)) : '' }; break;
  case 'borrar': if (!idOk(b.id)) return fail('Movimiento inválido.'); p = { id: String(b.id), nota: txt(b.nota, 200) }; break;
}
p._rol = rol;
return [{ json: { ok: true, op, rol, sql: SQL[op], params: ['', JSON.stringify(DEF), por, JSON.stringify(p), ''] } }];
