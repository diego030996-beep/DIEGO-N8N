// Prueba los nodos Code del flujo fuera de n8n: simula $('API') y la ejecución en el Postgres de prueba.
const fs = require('fs'), { execFileSync } = require('child_process');
const flujo = () => JSON.parse(fs.readFileSync(__dirname + '/../n8n/Panel general (ligas con PIN).json', 'utf8'));
const nodo = n => flujo().nodes.find(x => x.name === n);
const correr = (js, $, $input) => new Function('$', '$input', js)($, $input);
const lit = v => "'" + String(v).replace(/'/g, "''") + "'";
function pg(sql, params) {
  const q = sql.replace(/\$(\d+)/g, (m, i) => lit(params[i - 1]));
  try {
    const out = execFileSync('psql', ['-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1', '-c', q], { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
    const L = out.trim().split('\n'); return [{ json: { r: JSON.parse(L[L.length - 1]) } }];
  } catch (e) { return [{ json: { error: { message: String(e.stderr || e.message).split('\n')[0] } } }]; }
}
function pedir(body) {
  const nodes = { API: { first: () => ({ json: { body } }) } };
  const $ = n => nodes[n];
  const prep = correr(nodo('Preparar').parameters.jsCode, $)[0];
  if (!prep.json.ok) return prep.json.respuesta;
  nodes.Preparar = { first: () => prep };
  return correr(nodo('Armar respuesta').parameters.jsCode, $, { all: () => pg(prep.json.sql, prep.json.params) })[0].json.respuesta;
}
const psql = q => execFileSync('psql', ['-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1', '-c', q], { encoding: 'utf8' }).trim();
module.exports = { pedir, flujo, nodo, psql };
