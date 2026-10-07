// Toma el resultado de Postgres y arma la respuesta para la página. Si algo falló, explica qué.
const prep = $('Preparar').first().json;
let r = null, err = null;
for (const it of $input.all()) { const j = it.json || {}; if (j.r) r = j.r; else if (j.error || j.message) err = j; }
if (typeof r === 'string') { try { r = JSON.parse(r); } catch (e) { r = null; } }
let respuesta = r;
if (!r) {
  const e = err && (err.error || err);
  const m = [err && err.message, e && e.message, typeof e === 'string' ? e : ''].filter(Boolean).join(' · ').slice(0, 300);
  respuesta = { ok: false, msg: 'No se pudo completar (' + prep.op + '): ' + (m || 'la consulta no regresó datos.') };
}
return [{ json: { respuesta } }];
