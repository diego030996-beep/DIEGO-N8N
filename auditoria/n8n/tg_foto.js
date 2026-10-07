// Pasa la foto bajada de Telegram a base64 y arma la consulta para guardarla
const L = $('Leer mensaje').first().json;
const buf = await this.helpers.getBinaryDataBuffer(0, 'data');
if (buf.length > 2000000) return [{ json: { sql: "SELECT json_build_object('ok', false, 'msg', 'La foto pesa demasiado; mándala como foto, no como archivo.') AS r", params: [] } }];
const p = Object.assign({ _rol: 'admin', foto: buf.toString('base64') }, L.p);
return [{ json: { sql: L.sql, params: ['', L.def, 'Telegram', JSON.stringify(p), ''] } }];
