// Servidor de prueba que imita los webhooks de n8n: GET /webhook/compras y POST /webhook/compras-api
const http = require('http'), fs = require('fs');
const { pedir } = require('./nodos.js');
const flujo = () => JSON.parse(fs.readFileSync(__dirname + '/../n8n/Planeador de compras (Microsip).json', 'utf8'));
http.createServer((req, res) => {
  if (req.method === 'GET' && req.url.startsWith('/webhook/compras')) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(flujo().nodes.find(n => n.name === 'Mostrar página').parameters.responseBody);
  }
  let b = ''; req.on('data', d => b += d); req.on('end', () => {
    const body = JSON.parse(b || '{}');
    const rol = { 'k-compras': 'compras', 'k-auditor': 'auditor' }[body.k] || '';
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(pedir(body, rol)));
  });
}).listen(5679, () => console.log('listo'));
