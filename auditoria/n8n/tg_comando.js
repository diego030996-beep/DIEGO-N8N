// Respuestas a /pendientes y /folio
const L = $('Leer mensaje').first().json;
let r = $input.first().json.r; if (typeof r === 'string') r = JSON.parse(r);
const esc = t => String(t ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const $$ = n => '$' + Math.round(Number(n || 0)).toLocaleString('es-MX');
const EMO = { verde: '🟢', naranja: '🟠', rojo: '🔴', pendiente: '⏳' };
const fila = x => `${EMO[x.estado]} <b>${esc(x.folio)}</b> · ${$$(x.importe)} · ${esc(x.empleado || '?')}\n   ${esc(x.motivo)}`;
let text;
if (!r || !r.ok) text = '⚠️ No pude consultar: ' + esc((r && r.msg) || JSON.stringify($input.first().json.error || '').slice(0, 200));
else if (L.que === 'pendientes') {
  const s = r.resumen, P = r.lista.filter(x => x.estado !== 'verde');
  text = `🧾 <b>Auditoría de hoy</b>\n🟢 ${s.verde} · 🟠 ${s.naranja} · 🔴 ${s.rojo} · ⏳ ${s.pendiente}\n💰 ${$$(s.sin_comprobar)} sin comprobar` +
    (r.atrasados.n ? `\n⚠️ ${r.atrasados.n} de días anteriores (${$$(r.atrasados.monto)})` : '') +
    (P.length ? '\n\n' + P.slice(0, 15).map(fila).join('\n') + (P.length > 15 ? `\n…y ${P.length - 15} más.` : '') : '\n\n✅ Nada pendiente.');
} else {
  const R = r.lista || [];
  text = R.length ? `🔎 <b>${esc(L.q)}</b>\n\n` + R.slice(0, 8).map(x => fila(x) + `\n   ${String(x.fecha).slice(8, 10)}/${String(x.fecha).slice(5, 7)} · ${esc(x.concepto)}`).join('\n') : `No encontré <b>${esc(L.q)}</b>.`;
}
return [{ json: Object.assign({}, L.envio, { text: text.slice(0, 4000) }) }];
