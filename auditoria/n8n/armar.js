// Toma el resultado de Postgres y arma la respuesta para la página. Si algo falló, explica qué.
const prep = $('Preparar').first().json;
let r = null, err = null;
for (const it of $input.all()) { const j = it.json || {}; if (j.r) r = j.r; else if (j.error || j.message) err = j; }
if (typeof r === 'string') { try { r = JSON.parse(r); } catch (e) { r = null; } }
const QUE = { datos: 'leer los datos', tablero: 'leer el tablero', mis: 'leer tus movimientos', registrar: 'guardar el movimiento', actualizar: 'guardar los cambios',
  detalle: 'abrir el movimiento', revisar: 'guardar la revisión', vincular: 'vincular la compra', ignorar: 'guardar', buscar: 'buscar', empleado: 'guardar el empleado',
  config: 'guardar la configuración', borrar: 'borrar', corte: 'leer el corte de caja', firmar: 'firmar el corte', retiros_mes: 'leer los retiros del mes', pedidos: 'leer los pedidos' };
let respuesta = r;
if (!r) {
  const e = err && (err.error || err);
  const m = [err && err.message, e && e.message, typeof e === 'string' ? e : ''].filter(Boolean).join(' · ').slice(0, 400);
  const motivo = /statement timeout|canceling statement/i.test(m) ? 'tardó demasiado; intenta otra vez' : /mov_registro_retiro/.test(m) ? 'ese retiro ya lo reportaron'
    : m ? 'error de la base de datos (' + prep.op + '): ' + m : 'la consulta no regresó datos.';
  respuesta = { ok: false, msg: 'No se pudo ' + (QUE[prep.op] || 'completar') + ': ' + motivo };
} else if (prep.op === 'datos') { respuesta.rol = prep.rol; respuesta.yo = $('Acceso').first().json.nombre || ''; }
return [{ json: { respuesta } }];
