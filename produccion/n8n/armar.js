// Toma el resultado de Postgres y arma la respuesta para la página. Si algo falló, explica qué.
const prep = $('Preparar').first().json;
let r = null, err = null;
for (const it of $input.all()) { const j = it.json || {}; if (j.r) r = j.r; else if (j.error || j.message) err = j; }
if (typeof r === 'string') { try { r = JSON.parse(r); } catch (e) { r = null; } }
function textoError(j) {
  if (!j) return '';
  const e = j.error;
  const partes = [j.message, typeof e === 'string' ? e : null, e && e.message, e && e.description, e && e.detail, e && e.hint].filter(x => typeof x === 'string' && x.trim());
  const unicos = [...new Set(partes.map(x => x.trim()))];
  if (unicos.length) return unicos.join(' · ');
  try { return JSON.stringify(e || j).slice(0, 300); } catch (x) { return 'error desconocido'; }
}
const QUE = { datos: 'leer los datos', buscar: 'buscar', receta: 'guardar la receta', copiar: 'copiar la receta', capturar: 'guardar la producción',
  registros: 'leer la producción', borrar: 'borrar la captura', exportar: 'armar los archivos', importado: 'marcar como importado', materia: 'leer la materia prima',
  resumen: 'leer el resumen', precio: 'guardar el precio', extras: 'guardar los gastos', config: 'guardar la configuración',
  contar: 'guardar el pesaje', auditoria: 'leer la auditoría de polímero', merma: 'armar el ajuste por merma', folio_ms: 'buscar el folio en Microsip' };
let respuesta;
if (!r) {
  const m = textoError(err);
  const motivo = /statement timeout|canceling statement/i.test(m) ? 'tardó demasiado; intenta otra vez' : /lock timeout/i.test(m) ? 'la base estaba ocupada; intenta otra vez'
    : m ? 'error de la base de datos (' + prep.op + '): ' + m.slice(0, 400) : 'la consulta no regresó datos (' + prep.op + ').';
  respuesta = { ok: false, msg: 'No se pudo ' + (QUE[prep.op] || 'completar') + ': ' + motivo };
} else { respuesta = r; if (prep.op === 'datos') respuesta.rol = prep.rol; }
return [{ json: { respuesta } }];
