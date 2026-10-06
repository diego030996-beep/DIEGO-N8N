// Toma el resultado de Postgres y arma la respuesta para la página. Si algo falló, explica qué.
const prep = $('Preparar').first().json;
let r = null, err = null;
for (const it of $input.all()) {
  const j = it.json || {};
  if (j.r) r = j.r;
  if (j.error) err = j.error;
}
if (typeof r === 'string') { try { r = JSON.parse(r); } catch (e) { r = null; } }
const QUE = { datos: 'leer los datos', planeador: 'leer el planeador', guardar: 'guardar', razon: 'guardar la razón', folio: 'ligar el folio',
  registro: 'leer el registro', reconstruir: 'reconstruir el mes', calcular: 'calcular', ocs: 'leer las OCs', reporte: 'leer el reporte',
  buscar: 'buscar', articulo: 'guardar el artículo', config: 'guardar la configuración' };
let respuesta;
if (!r) {
  const m = String((err && (err.message || err)) || '');
  const motivo = /statement timeout|canceling statement/i.test(m) ? 'tardó demasiado; intenta otra vez en un momento'
    : /lock timeout/i.test(m) ? 'la base estaba ocupada; intenta otra vez' : m.slice(0, 240);
  respuesta = { ok: false, msg: 'No se pudo ' + (QUE[prep.op] || 'completar') + (motivo ? ': ' + motivo : '.') };
} else {
  respuesta = r;
  if (prep.op === 'datos') respuesta.rol = prep.rol;
}
return [{ json: { respuesta, desde: prep.desde } }];
