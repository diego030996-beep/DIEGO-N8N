// Servidor de prueba que imita los webhooks de n8n: GET /webhook/produccion-tinacos y POST /webhook/produccion-tinacos-api
const http = require('http');
const { pedir, flujo } = require('./nodos.js');
http.createServer((req, res) => {
  if (req.method === 'GET' && req.url.startsWith('/webhook/produccion-tinacos')) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(flujo().nodes.find(n => n.name === 'Mostrar página').parameters.responseBody);
  }
  let b = ''; req.on('data', d => b += d); req.on('end', () => {
    const body = JSON.parse(b || '{}');
    const rol = { 'k-prod': 'produccion', 'k-auditor': 'auditor' }[body.k] || '';
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(rol ? pedir(body, rol) : { ok: false, msg: 'Esta liga no tiene permiso.' }));
  });
}).listen(5681, () => console.log('listo'));
