// Resumen del día al cierre, para el encargado y el dueño
const cfg = $('Configuración del bot').first().json;
let r = $input.first().json.r; if (typeof r === 'string') r = JSON.parse(r);
if (!r || !r.ok) throw new Error('No se pudo leer el resumen: ' + JSON.stringify($input.first().json.error || r).slice(0, 300));
const esc = t => String(t ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const $$ = n => '$' + Math.round(Number(n || 0)).toLocaleString('es-MX');
const EMO = { verde: '🟢', naranja: '🟠', rojo: '🔴', pendiente: '⏳' };
const s = r.resumen, P = r.lista.filter(x => x.estado === 'rojo' || x.estado === 'naranja');
const f = r.desde;
const text = `📊 <b>Auditoría del día ${f.slice(8, 10)}/${f.slice(5, 7)}</b>\n` +
  `🟢 ${s.verde} cuadrados · 🟠 ${s.naranja} por revisar · 🔴 ${s.rojo} inconsistencias\n💰 <b>${$$(s.sin_comprobar)}</b> sin comprobar` +
  (r.atrasados.n ? `\n⚠️ ${r.atrasados.n} de días anteriores sin resolver (${$$(r.atrasados.monto)})` : '') +
  (P.length ? '\n\n' + P.slice(0, 12).map(x => `${EMO[x.estado]} ${esc(x.folio)} · ${$$(x.importe)} · ${esc(x.empleado || '?')} — ${esc(x.motivo)}`).join('\n') + (P.length > 12 ? `\n…y ${P.length - 12} más.` : '')
    : '\n\n✅ Todo comprobado.') +
  (r.por_empleado.some(e => e.problemas) ? '\n\n<b>Por persona:</b> ' + r.por_empleado.filter(e => e.problemas).map(e => `${esc(e.nombre)} ${e.problemas} (${$$(e.sin_comprobar)})`).join(' · ') : '');
return [{ json: { chat_id: String(cfg.chat_id).trim(), parse_mode: 'HTML', disable_web_page_preview: true, text: text.slice(0, 4000) } }];
