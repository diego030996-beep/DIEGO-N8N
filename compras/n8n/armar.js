// Toma el resultado de Postgres y arma la respuesta para la página. Si algo falló, explica qué.
const prep = $('Preparar').first().json;
let r = null, err = null;
for (const it of $input.all()) {
  const j = it.json || {};
  if (j.r) r = j.r;
  else if (j.error || j.message) err = j;
}
if (typeof r === 'string') { try { r = JSON.parse(r); } catch (e) { r = null; } }
// n8n deja el texto del error en distintos lugares según la versión: message, error.message, error.description...
function textoError(j) {
  if (!j) return '';
  const e = j.error;
  const partes = [j.message, typeof e === 'string' ? e : null, e && e.message, e && e.description, e && e.detail, e && e.hint,
                  e && e.cause && e.cause.message]
    .filter(x => typeof x === 'string' && x.trim());
  const unicos = [...new Set(partes.map(x => x.trim()))];
  if (unicos.length) return unicos.join(' · ');
  try { return JSON.stringify(e || j).slice(0, 300); } catch (x) { return 'error desconocido'; }
}
const QUE = { datos: 'leer los datos', planeador: 'leer el planeador', guardar: 'guardar', razon: 'guardar la razón', folio: 'ligar el folio',
  registro: 'leer el registro', reconstruir: 'reconstruir el mes', calcular: 'calcular', ocs: 'leer las OCs', reporte: 'leer el reporte',
  buscar: 'buscar', articulo: 'guardar el artículo', config: 'guardar la configuración', limpieza: 'revisar el catálogo',
  revision: 'guardar la decisión', gerencia: 'poner la autorización de gerencia', reactivar: 'regresar el artículo' };
let respuesta;
if (!r) {
  const m = textoError(err);
  const motivo = /statement timeout|canceling statement/i.test(m) ? 'tardó demasiado; intenta otra vez en un momento'
    : /lock timeout/i.test(m) ? 'la base estaba ocupada; intenta otra vez'
    : m ? 'error de la base de datos (' + prep.op + '): ' + m.slice(0, 400) : 'la consulta no regresó datos (' + prep.op + ').';
  respuesta = { ok: false, msg: 'No se pudo ' + (QUE[prep.op] || 'completar') + ': ' + motivo };
} else {
  respuesta = r;
  if (prep.op === 'datos') respuesta.rol = prep.rol;
}
return [{ json: { respuesta, desde: prep.desde } }];
