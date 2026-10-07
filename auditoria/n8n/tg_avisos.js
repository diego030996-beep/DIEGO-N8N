// Un mensaje por cada problema vencido (para poder contestarle con la foto). Etiqueta al responsable si mandó por Telegram.
// Máximo 8 mensajes por corrida; el resto va en uno solo de resumen.
const cfg = $('Configuración del bot').first().json;
let r = $input.first().json.r || {}; if (typeof r === 'string') r = JSON.parse(r);
const A = r.avisos || [];
if (!A.length) return [];
const esc = t => String(t ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const $$ = n => '$' + Number(Math.abs(n || 0)).toLocaleString('es-MX', { maximumFractionDigits: 2 });
const quien = a => a.tg_user ? `<a href="tg://user?id=${encodeURIComponent(a.tg_user)}">${esc(a.empleado)}</a>` : esc(a.empleado || '?');
const falta = a => a.clase === 'retiro' ? 'que alguien lo reporte con su ticket' : a.clase === 'compra' ? 'el comprobante de la compra'
  : /COMPRA NO REGISTRADA/.test(a.motivo) ? 'registrar la compra en Microsip' : /FALTA COMPROBANTE/.test(a.motivo) ? 'la foto del ticket' : a.motivo;
const ref = a => a.clase === 'retiro' ? 'retiro ' + a.folio : a.clase === 'compra' ? 'compra ' + a.folio : 'M-' + String(a.clave).split(':')[1];
const chat = String(cfg.chat_id).trim();
const out = A.slice(0, 8).map(a => ({ json: { chat_id: chat, parse_mode: 'HTML', disable_web_page_preview: true, claves: [a.clave],
  text: `${a.estado === 'rojo' ? '🔴' : '🟠'} <b>${esc(a.folio)}</b> · ${$$(a.importe)} · ${quien(a)}` + (a.pedido ? `\nPedido ${esc(a.pedido)}` : '') +
    `\n${esc(String(a.concepto).slice(0, 90))}\nFalta: ${esc(falta(a))}${a.horas > 0 ? ' · venció hace ' + a.horas + ' h' : ''}` +
    '\n↩️ Responde a este mensaje con la foto.' + `\n<i>Ref: ${esc(ref(a))}</i>` } }));
if (A.length > 8) {
  const R = A.slice(8);
  out.push({ json: { chat_id: chat, parse_mode: 'HTML', claves: R.map(a => a.clave),
    text: `⚠️ <b>Y ${R.length} pendientes más</b>\n` + R.slice(0, 25).map(a => `${a.estado === 'rojo' ? '🔴' : '🟠'} ${esc(a.folio)} · ${$$(a.importe)} · ${esc(a.empleado || '?')}`).join('\n') +
      '\n\nEscribe /pendientes para ver la lista.' } });
}
return out;
