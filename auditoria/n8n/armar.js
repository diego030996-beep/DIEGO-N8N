// Toma el resultado de Postgres y arma la respuesta para la página. Si algo falló, explica qué.
// Al firmar un corte o registrar un retiro del dueño, también arma el comprobante que se manda a Telegram (respaldo).
const prep = $('Preparar').first().json;
let r = null, err = null;
for (const it of $input.all()) { const j = it.json || {}; if (j.r) r = j.r; else if (j.error || j.message) err = j; }
if (typeof r === 'string') { try { r = JSON.parse(r); } catch (e) { r = null; } }
const QUE = { datos: 'leer los datos', tablero: 'leer el tablero', mis: 'leer tus movimientos', registrar: 'guardar el movimiento', actualizar: 'guardar los cambios',
  detalle: 'abrir el movimiento', revisar: 'guardar la revisión', vincular: 'vincular la compra', ignorar: 'guardar', buscar: 'buscar', empleado: 'guardar el empleado',
  config: 'guardar la configuración', borrar: 'borrar', corte: 'leer el corte de caja', firmar: 'firmar el corte', retiros_mes: 'leer los retiros del mes', pedidos: 'leer los pedidos',
  retiro_dueno: 'guardar el retiro', retiros_dueno: 'leer los retiros del dueño' };
let respuesta = r, telegram = '';
const esc = t => String(t ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const $$ = n => (Number(n) < 0 ? '-$' : '$') + Math.abs(Number(n || 0)).toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fecha = f => String(f || '').slice(8, 10) + '/' + String(f || '').slice(5, 7) + '/' + String(f || '').slice(0, 4);
const hora = t => new Date(t).toLocaleString('es-MX', { timeZone: 'America/Mexico_City', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
if (!r) {
  const e = err && (err.error || err);
  const m = [err && err.message, e && e.message, typeof e === 'string' ? e : ''].filter(Boolean).join(' · ').slice(0, 400);
  const motivo = /statement timeout|canceling statement/i.test(m) ? 'tardó demasiado; intenta otra vez' : /mov_registro_retiro/.test(m) ? 'ese retiro ya lo reportaron'
    : /mov_retiro_dueno_ms/.test(m) ? 'ese retiro ya está registrado como del dueño'
    : m ? 'error de la base de datos (' + prep.op + '): ' + m : 'la consulta no regresó datos.';
  respuesta = { ok: false, msg: 'No se pudo ' + (QUE[prep.op] || 'completar') + ': ' + motivo };
} else if (prep.op === 'datos') { respuesta.rol = prep.rol; respuesta.yo = $('Acceso').first().json.nombre || ''; }
else if (prep.op === 'firmar' && r.ok) {
  const t = r.totales || {};
  telegram = `✍️ <b>CORTE DE CAJA FIRMADO</b> — ${fecha(r.fecha)}\n\n` +
    (r.formas || []).map(f => `${f.sin_comprobante ? '💵' : '💳'} ${esc(f.forma)}: ${$$(f.importe)}${f.faltan ? ' (faltan ' + f.faltan + ' comprobantes)' : ''}`).join('\n') +
    `\n\nRetiros: ${$$(t.retiros)}` + (Number(t.retiros_dueno) ? `\nRetiros del dueño: ${$$(t.retiros_dueno)}` : '') +
    `\nEfectivo esperado: <b>${$$(r.esperado)}</b>\nEfectivo entregado: <b>${$$(r.entregado)}</b>\nDiferencia: <b>${$$(r.diferencia)}</b>` +
    (r.pendientes ? `\n⚠️ Al firmar quedaban ${r.pendientes} sin comprobar (${$$(r.pendiente_monto)})` : '\n✅ Todo comprobado') +
    (r.nota ? `\nNota: ${esc(r.nota)}` : '') +
    `\n\nFirmó: ${esc(r.por)} · ${hora(r.en)}\nHuella: <code>${esc(r.huella)}</code>`;
} else if (prep.op === 'retiro_dueno' && r.ok && r.retiro) {
  const x = r.retiro;
  telegram = x.anulado
    ? `❌ <b>RETIRO DEL DUEÑO ANULADO</b> — RD-${x.id}\n${$$(x.importe)} · ${fecha(x.fecha)} ${esc(x.hora || '')}\nMotivo: ${esc(x.anulado_nota || '')}\nHuella original: <code>${esc(x.huella)}</code>`
    : `💵 <b>RETIRO DEL DUEÑO</b> — RD-${x.id}\n\nImporte: <b>${$$(x.importe)}</b>\nFecha: ${fecha(x.fecha)} ${esc(x.hora || '')}` +
      (x.retiro_folio ? `\nRetiro en Microsip: ${esc(x.retiro_folio)}` : '\nNo está capturado en Microsip (se descuenta del corte)') +
      (x.nota ? `\nNota: ${esc(x.nota)}` : '') + `\n\nRegistró: ${esc(x.por)} · ${hora(x.creado)}\nHuella: <code>${esc(x.huella)}</code>`;
}
return [{ json: { respuesta, telegram } }];
