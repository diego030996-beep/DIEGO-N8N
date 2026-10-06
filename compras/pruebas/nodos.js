// Prueba los nodos Code del flujo fuera de n8n: simula $('API'), $('Acceso') y la ejecución en Postgres de prueba.
const fs = require('fs'), { execFileSync } = require('child_process');
const flujo = JSON.parse(fs.readFileSync(__dirname + '/../n8n/Planeador de compras (Microsip).json', 'utf8'));
const code = n => flujo.nodes.find(x => x.name === n).parameters.jsCode;
function correrCode(js, ctx) { return new Function('$', '$input', js)(ctx.$, ctx.$input); }
const lit = v => "'" + String(v).replace(/'/g, "''") + "'";
function pg(sql, params) {
  const q = sql.replace(/\$(\d+)/g, (m, i) => lit(params[i - 1]));
  try {
    const out = execFileSync('psql', ['-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1', '-c', q], { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
    const i = out.lastIndexOf('{"ok"'); return i >= 0 ? [{ json: { r: JSON.parse(out.slice(i).split('\nINSERT')[0].split('\nUPDATE')[0]) } }] : [{ json: {} }];
  } catch (e) { return [{ json: { error: { message: String(e.stderr).split('\n')[0] } } }]; }
}
function pedir(body, rol = 'compras') {
  const nodes = { API: { isExecuted: true, first: () => ({ json: { body } }) }, Acceso: { first: () => ({ json: { rol, razones: null } }) } };
  const $ = n => nodes[n];
  const prep = correrCode(code('Preparar'), { $ })[0];
  if (!prep.json.ok) return prep.json.respuesta;
  nodes.Preparar = { first: () => prep };
  const res = pg(prep.json.sql, prep.json.params);
  return correrCode(code('Armar respuesta'), { $, $input: { all: () => res } })[0].json.respuesta;
}
module.exports = { pedir };
if (require.main === module) {
  const r = pedir(JSON.parse(process.argv[2]), process.argv[3] || 'compras');
  console.log(JSON.stringify(r).slice(0, 1500));
}
