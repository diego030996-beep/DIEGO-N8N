// Un solo mensaje con lo que pasó la hora límite y sigue mal (🔴 o 🟠), a cada chat configurado. Se registra todo en la web.
const chats = $('Origen').first().json.chats;
let r = $input.first().json.r || {}; if (typeof r === 'string') r = JSON.parse(r);
const A = r.avisos || [];
if (!A.length) return [];
const esc = t => String(t ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const $$ = n => '$' + Number(Math.abs(n || 0)).toLocaleString('es-MX', { maximumFractionDigits: 2 });
const falta = a => {
  if (a.clase === 'retiro') return 'reportarlo + ticket';
  if (a.clase === 'cobro') return String(a.motivo).replace(/^FALTA /, '').toLowerCase();
  if (a.clase === 'compra') return 'comprobante de la compra';
  if (/FALTA COMPROBANTE/.test(a.motivo)) return a.tipo === 'compra' ? 'ticket + recepción de compra en Microsip' : 'ticket';
  if (/FALTA RECEPCI/.test(a.motivo)) return 'recepción de compra en Microsip';
  return a.motivo;
};
const L = A.slice(0, 20).map(a => `${a.estado === 'rojo' ? '🔴' : '🟠'} <b>${esc(a.folio)}</b> · ${$$(a.importe)} · ${esc(a.empleado || '?')}` +
  (a.pedido ? `\nPedido ${esc(a.pedido)}` : '') + `\n${esc(String(a.concepto).slice(0, 90))}` +
  `\nFalta: ${esc(falta(a))}${a.horas > 0 ? ' · ' + a.horas + ' h' : ''}`);
const text = `⚠️ <b>Comprobación pendiente</b>${A.length > 1 ? ' (' + A.length + ')' : ''}\n\n` + L.join('\n\n') +
  (A.length > 20 ? `\n\n…y ${A.length - 20} más.` : '') + '\n\nSe completa en Mis ligas → 🧾 Auditoría de movimientos.';
const claves = A.map(a => a.clave);
return chats.map(chat_id => ({ json: { chat_id, text: text.slice(0, 4000), claves } }));
