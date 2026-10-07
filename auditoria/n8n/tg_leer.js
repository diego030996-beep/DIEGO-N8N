// Lee lo que mandan al grupo de choferes. Solo atiende: fotos con folio/importe (o en respuesta a un aviso del bot) y los comandos.
const SQL = __SQL__;
const DEF = __DEF__;
const cfg = $('Configuración del bot').first().json;
const w = $('Telegram').first().json;
const h = w.headers || {}, u = w.body || {};
if (String(cfg.secreto || '') && h['x-telegram-bot-api-secret-token'] !== String(cfg.secreto)) return [];
const m = u.message;
if (!m || !m.chat || String(m.chat.id) !== String(cfg.chat_id).trim()) return [];
const reply = { message_id: m.message_id, allow_sending_without_reply: true };
const base = { chat_id: String(m.chat.id), reply_parameters: reply, parse_mode: 'HTML', disable_web_page_preview: true };
const consulta = (op, p) => ({ sql: SQL[op], params: ['', JSON.stringify(DEF), 'Telegram', JSON.stringify(Object.assign({ _rol: 'admin' }, p)), ''] });
const AYUDA = '🧾 <b>Auditoría de movimientos</b>\n' +
  'Manda la <b>foto del ticket</b> con el folio del retiro y lo que se compró:\n<code>R-01842 500 P4509 block ligero</code>\n\n' +
  'Sin retiro de caja (tarjeta, transferencia):\n<code>350 gasolina tarjeta</code>\n\n' +
  'O <b>responde con la foto</b> a un aviso del bot.\n\n' +
  '<code>/pendientes</code> – lo que falta comprobar\n<code>/folio R-01842</code> – cómo va un movimiento';
const texto = String(m.caption || m.text || '').trim();
const cmd = texto.match(/^\/([a-záéíóú]+)(?:@\w+)?\s*([\s\S]*)$/i);
const foto = m.photo && m.photo.length ? m.photo[m.photo.length - 1] : (m.document && /^image\/(jpe?g|png|webp)/.test(m.document.mime_type || '') ? m.document : null);
if (cmd && !foto) {
  const c = cmd[1].toLowerCase(), arg = cmd[2].trim();
  if (/^(pendientes|auditoria|auditoría)$/.test(c)) return [{ json: Object.assign({ ruta: 'comando', que: 'pendientes' }, consulta('tablero', { ver: 'problemas' }), { envio: base }) }];
  if (/^(folio|buscar)$/.test(c)) {
    if (arg.length < 2) return [{ json: { ruta: 'texto', envio: Object.assign({ text: 'Escribe así: <code>/folio R-01842</code>' }, base) } }];
    return [{ json: Object.assign({ ruta: 'comando', que: 'folio', q: arg.slice(0, 40) }, consulta('buscar', { q: arg.slice(0, 40) }), { envio: base }) }];
  }
  if (/^(comprobante|ayuda|help|start)$/.test(c)) return [{ json: { ruta: 'texto', envio: Object.assign({ text: AYUDA }, base) } }];
  return [];
}
if (!foto) return [];
// ---- datos del texto de la foto (o del aviso al que contesta) ----
const rep = m.reply_to_message && m.reply_to_message.from && m.reply_to_message.from.is_bot ? String(m.reply_to_message.text || m.reply_to_message.caption || '') : '';
let T = ' ' + texto.replace(/\s+/g, ' ') + ' ';
const sacar = re => { const x = T.match(re); if (x) T = T.replace(x[0], ' '); return x; };
const ref = rep.match(/Ref: (?:retiro \D*0*(\d+)|M-(\d+)|compra (\S+))/);
let retiro = ref && ref[1] || '', registro = ref && ref[2] || '', compra = ref && ref[3] || '';
const xr = sacar(/[\s(]R[-\s#]?0*(\d{2,7})(?=[\s,.)]|$)/i) || sacar(/\sretiro\s*#?\s*0*(\d{2,7})(?=[\s,.)])/i);
if (xr) retiro = xr[1];
const xm = sacar(/\sM-(\d{1,9})(?=[\s,.)])/i); if (xm) registro = xm[1];
const xp = sacar(/[\s(]P[-\s]?0*(\d{2,7})(?=[\s,.)])/i);
const pedido = xp ? 'P' + xp[1] : '';
const xi = sacar(/\$\s*(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)/) || sacar(/\s(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d{1,6}(?:\.\d{1,2})?)(?=\s)/);
const importe = xi ? String(Number(xi[1].replace(/,/g, ''))) : '';
const t = texto.toLowerCase();
const metodo = /transfer|spei/.test(t) ? 'transferencia' : /tarjeta|terminal|tdc|tdd|d[eé]bito|cr[eé]dito/.test(t) ? 'tarjeta' : 'efectivo';
const tipo = /gasolina|diesel|di[eé]sel|combustible|magna|premium/.test(t) ? 'gasolina' : /dep[oó]sito|deposit/.test(t) ? 'deposito'
  : /gasto|flete|comida|propina|refacci|taller|caseta|estacionamiento|papeler/.test(t) ? 'gasto' : 'compra';
const concepto = T.replace(/\b(efectivo|transferencia|spei|tarjeta|terminal)\b/gi, ' ').replace(/\s+/g, ' ').trim().slice(0, 200);
if (!retiro && !registro && !compra && !importe) {
  // foto suelta: solo se contesta si la mencionan como comprobante; si no, puede ser otra cosa del grupo
  if (!/comprobante|ticket|factura|retiro|gasto|gasolina/.test(t)) return [];
  return [{ json: { ruta: 'texto', envio: Object.assign({ text: '¿De qué retiro es? Mándala otra vez con el folio y el importe, por ejemplo:\n<code>R-01842 500 block ligero</code>' }, base) } }];
}
if (foto.file_size && foto.file_size > 8e6) return [{ json: { ruta: 'texto', envio: Object.assign({ text: '⚠️ Esa imagen es muy pesada; mándala como foto (no como archivo).' }, base) } }];
const from = m.from || {};
const p = { retiro_num: retiro, registro_id: registro, compra_folio: compra, importe, pedido, concepto, tipo, metodo,
  tg_user: String(from.id || ''), tg_nombre: [from.first_name, from.last_name].filter(Boolean).join(' ').toUpperCase().slice(0, 40) };
return [{ json: { ruta: 'foto', file_id: foto.file_id, p, sql: SQL.tg_registrar, detalle: SQL.detalle, def: JSON.stringify(DEF), envio: base } }];
