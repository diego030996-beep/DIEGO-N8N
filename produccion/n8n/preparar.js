// Producción de tinacos: revisa lo que pide la página y arma UNA consulta para Postgres (con límite de tiempo).
const SQL = __SQL__;
const DEF = __DEF__;
const hoyMX = new Date(Date.now() - 6 * 3600000).toISOString().slice(0, 10);   // Ciudad de México (UTC-6)
const arma = (op, p, por, rol) => [{ json: { ok: true, op, rol, sql: SQL[op], params: ['', JSON.stringify(DEF), String(por).slice(0, 80), JSON.stringify(p || {}), ''] } }];
const fail = msg => [{ json: { ok: false, respuesta: { ok: false, msg } } }];
const rol = String($('Acceso').first().json.rol || '');
if (!rol) return fail('Esta liga no tiene permiso. Pide la liga de producción al administrador.');
const b = $('API').first().json.body || {};
const op = String(b.op || '');
if (!SQL[op]) return fail('Operación desconocida.');
const ESCRIBE = ['receta', 'copiar', 'capturar', 'borrar', 'exportar', 'importado', 'precio', 'extras', 'config'];
if (rol === 'auditor' && ESCRIBE.includes(op) && !(op === 'exportar' && b.marcar !== 'si')) return fail('Esta liga es solo de consulta.');
const quien = String(b.quien || '').replace(/[^\p{L}\p{N} .\-]/gu, '').trim().slice(0, 40);
const por = quien ? quien + ' (' + rol + ')' : rol;
const txt = (v, n) => String(v ?? '').replace(/\s+/g, ' ').trim().slice(0, n);
const fechaOk = v => /^\d{4}-\d{2}-\d{2}$/.test(String(v || '')) && String(v) >= '2020-01-01';
const idOk = v => Number.isInteger(Number(v)) && Number(v) > 0 && Number(v) < 1e15;
const cantOk = (v, max) => isFinite(Number(v)) && Number(v) > 0 && Number(v) <= max;
const rango = () => {
  const d = b.desde ? String(b.desde) : '', h = b.hasta ? String(b.hasta) : '';
  if ((d && !fechaOk(d)) || (h && !fechaOk(h))) return null;
  return { desde: d, hasta: h };
};
let p = {};
switch (op) {
  case 'datos': break;
  case 'buscar': p = { q: txt(b.q, 60) }; if (p.q.length < 2) return fail('Escribe al menos 2 letras.'); break;
  case 'receta': {
    if (!idOk(b.articulo_id)) return fail('Tinaco inválido.');
    const L = Array.isArray(b.comps) ? b.comps : [];
    if (L.length > 40) return fail('Demasiados componentes.');
    for (const c of L) { if (!idOk(c.componente_id)) return fail('Componente inválido.'); if (!cantOk(c.cantidad, 100000)) return fail('Cantidad inválida en la receta.');
      if (Number(c.componente_id) === Number(b.articulo_id)) return fail('Un tinaco no puede ser componente de sí mismo.'); }
    p = { articulo_id: Number(b.articulo_id), comps: L.map(c => ({ componente_id: Number(c.componente_id), cantidad: String(Number(c.cantidad)) })) };
    break; }
  case 'copiar': {
    const a = Array.isArray(b.a) ? b.a : [];
    if (!idOk(b.de) || !a.length || a.length > 100 || !a.every(idOk)) return fail('Elige el tinaco de origen y a cuáles copiar.');
    if ((b.cambiar_de && !idOk(b.cambiar_de)) || (b.cambiar_a && !idOk(b.cambiar_a))) return fail('Componente inválido.');
    p = { de: Number(b.de), a: a.map(Number), cambiar_de: b.cambiar_de ? String(Number(b.cambiar_de)) : '', cambiar_a: b.cambiar_a ? String(Number(b.cambiar_a)) : '' };
    break; }
  case 'capturar': {
    if (!fechaOk(b.fecha) || b.fecha > hoyMX) return fail('Fecha inválida (no puede ser de mañana).');
    const L = Array.isArray(b.lineas) ? b.lineas : [];
    if (!L.length || L.length > 100) return fail('Captura al menos un tinaco.');
    for (const l of L) { if (!idOk(l.articulo_id)) return fail('Tinaco inválido.'); if (!cantOk(l.cantidad, 10000) || !Number.isInteger(Number(l.cantidad))) return fail('Cantidad inválida (piezas enteras).'); }
    p = { fecha: b.fecha, nota: txt(b.nota, 200), lineas: L.map(l => ({ articulo_id: Number(l.articulo_id), cantidad: String(Number(l.cantidad)) })) };
    break; }
  case 'registros': case 'materia': case 'resumen': { const r = rango(); if (!r) return fail('Fechas inválidas.'); p = r; break; }
  case 'borrar': if (!idOk(b.id)) return fail('Captura inválida.'); p = { id: Number(b.id) }; break;
  case 'exportar':
    if (b.exporte_id) { if (!idOk(b.exporte_id)) return fail('Exporte inválido.'); p = { exporte_id: String(Number(b.exporte_id)) }; }
    else { const r = rango(); if (!r) return fail('Fechas inválidas.'); p = { ...r, marcar: b.marcar === 'si' ? 'si' : '' }; }
    break;
  case 'importado': if (!idOk(b.exporte_id)) return fail('Exporte inválido.'); p = { exporte_id: Number(b.exporte_id), quitar: b.quitar === 'si' ? 'si' : '' }; break;
  case 'precio':
    if (!idOk(b.articulo_id)) return fail('Tinaco inválido.');
    if (b.precio !== '' && b.precio != null && !cantOk(b.precio, 1e7)) return fail('Precio inválido.');
    p = { articulo_id: Number(b.articulo_id), precio: b.precio === '' || b.precio == null ? '' : String(Number(b.precio)) };
    break;
  case 'extras': {
    const L = Array.isArray(b.lista) ? b.lista : [];
    if (L.length > 30) return fail('Demasiados conceptos.');
    for (const x of L) { if (!txt(x.concepto, 60)) return fail('Falta el concepto.'); if (!isFinite(Number(x.monto)) || Number(x.monto) < 0 || Number(x.monto) > 1e6) return fail('Monto inválido.');
      if (x.articulo_id && !idOk(x.articulo_id)) return fail('Tinaco inválido.'); }
    p = { lista: L.map(x => ({ concepto: txt(x.concepto, 60), monto: String(Number(x.monto)), articulo_id: x.articulo_id ? String(Number(x.articulo_id)) : '' })) };
    break; }
  case 'config': {
    const g = b.general || {}, OK = { lineas: 200, almacenes: 200, iva: 5, empresa: 80, tienda: 80 }, general = {};
    for (const [k, v] of Object.entries(g)) { if (!(k in OK)) return fail('Ajuste desconocido: ' + k); general[k] = txt(v, OK[k]); }
    for (const k of ['lineas', 'almacenes']) if (general[k]) { try { new RegExp(general[k], 'i'); } catch (e) { return fail('Texto inválido en ' + k + '.'); } }
    if (general.iva && !(Number(general.iva) >= 0 && Number(general.iva) <= 30)) return fail('IVA inválido.');
    p = { general };
    break; }
}
return arma(op, p, por, rol);
