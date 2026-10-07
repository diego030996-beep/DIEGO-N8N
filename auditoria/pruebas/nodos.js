// Prueba los nodos del flujo fuera de n8n: corre Acceso, Preparar, la consulta y Armar respuesta contra el Postgres de prueba (base auditoria).
const fs = require('fs'), { execFileSync } = require('child_process');
const flujo = () => JSON.parse(fs.readFileSync(__dirname + '/../n8n/Auditoría de movimientos (Microsip).json', 'utf8'));
const nodo = n => flujo().nodes.find(x => x.name === n);
const correr = (js, $, $input) => new Function('$', '$input', js)($, $input);
const lit = v => v == null ? 'NULL' : "'" + String(v).replace(/'/g, "''") + "'";
const AHORA = process.env.AHORA || '';
function pg(sql, params) {
  if (AHORA) params = params.map((v, i) => i === 4 && v === '' ? AHORA : v);
  const q = sql.replace(/\$(\d+)/g, (m, i) => lit(params[i - 1]));
  try {
    const out = execFileSync('psql', ['-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres', '-d', 'auditoria', '-qAt', '-F', '\t', '-v', 'ON_ERROR_STOP=1', '-c', q],
      { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 64 << 20 });
    return out;
  } catch (e) { return { error: { message: String(e.stderr).split('\n')[0] } }; }
}
function acceso(k) {
  const out = pg(nodo('Acceso').parameters.query, [k]);
  const [rol, nombre] = String(out).trim().split('\n').pop().split('\t');
  return { rol: rol || '', nombre: nombre || '' };
}
function pedir(body) {
  const acc = acceso(String(body.k || ''));
  const nodes = { API: { first: () => ({ json: { body } }) }, Acceso: { first: () => ({ json: acc }) } };
  const $ = n => nodes[n];
  const prep = correr(nodo('Preparar').parameters.jsCode, $)[0];
  if (!prep.json.ok) return prep.json.respuesta;
  nodes.Preparar = { first: () => prep };
  const out = pg(prep.json.sql, prep.json.params);
  const res = typeof out === 'string' ? (() => { const i = out.lastIndexOf('{"ok"'); return [{ json: i >= 0 ? { r: JSON.parse(out.slice(i).trim()) } : {} }]; })() : [{ json: out }];
  return correr(nodo('Armar respuesta').parameters.jsCode, $, { all: () => res })[0].json.respuesta;
}
function foto(k, id) {
  const out = pg(nodo('Buscar foto').parameters.query, [k, String(id)]);
  const f = typeof out === 'string' ? out.trim().split('\n').pop() : '';
  return correr(nodo('Foto a imagen').parameters.jsCode, null, { first: () => ({ json: { foto: f } }) })[0];
}
module.exports = { pedir, foto, flujo, nodo, pg };
