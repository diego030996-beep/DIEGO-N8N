// Después de guardar: pide el expediente para contestar con el semáforo (o pasa el error)
const L = $('Leer mensaje').first().json;
let r = $input.first().json.r; if (typeof r === 'string') r = JSON.parse(r);
r = r || { ok: false, msg: 'No se pudo guardar: ' + JSON.stringify($input.first().json.error || '').slice(0, 300) };
if (!r.ok || !r.id) return [{ json: { guardado: r, sql: "SELECT json_build_object('ok', false) AS r", params: [] } }];
return [{ json: { guardado: r, sql: L.detalle, params: ['', L.def, 'Telegram', JSON.stringify({ _rol: 'admin', clase: 'registro', ref: String(r.id) }), ''] } }];
