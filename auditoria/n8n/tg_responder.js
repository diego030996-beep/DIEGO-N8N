// Contesta en el grupo con el resultado: 🟢 cuadrado, 🟠 qué falta, ⏳ en plazo, o el error
const L = $('Leer mensaje').first().json, g = $('Pedir estado').first().json.guardado;
let d = $input.first().json.r; if (typeof d === 'string') d = JSON.parse(d);
const esc = t => String(t ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const $$ = n => '$' + Number(n || 0).toLocaleString('es-MX', { maximumFractionDigits: 2 });
const EMO = { verde: '🟢', naranja: '🟠', rojo: '🔴', pendiente: '⏳' };
let text;
if (!g.ok) text = '⚠️ ' + esc(g.msg || 'No se pudo guardar.');
else if (!d || !d.ok) text = '✅ Guardado (M-' + g.id + ').';
else {
  const m = d.mov, x = d.registro || {};
  text = `${EMO[m.estado] || ''} <b>${esc(m.folio)}</b> · ${$$(m.importe)} · ${esc(m.empleado)}\n${esc(m.concepto)}\n` +
    `Comprobado ${$$(m.comprobado)} de ${$$(m.importe)} · ${d.comprobantes.length} foto${d.comprobantes.length === 1 ? '' : 's'}\n` +
    (m.estado === 'verde' ? '✓ Cuadrado' : esc(m.motivo)) +
    (x.compra ? `\nCompra Microsip: ${esc(x.compra.folio)} · ${$$(x.compra.total)}` : x.req_compra ? '\nCompra Microsip: todavía no está registrada' : '') +
    (x.pedido ? `\nPedido: ${esc(x.pedido.folio || x.pedido.escrito)}${x.pedido.folio ? (x.pedido.cancelado ? ' (CANCELADO)' : '') : ' (no existe en Microsip)'}` : '') +
    (m.estado === 'pendiente' && m.vence ? `\n⏰ Tiene hasta las ${m.vence.slice(11)} h` : '') +
    `\n<i>Ref: M-${x.id}</i>`;
}
return [{ json: Object.assign({}, L.envio, { text }) }];
