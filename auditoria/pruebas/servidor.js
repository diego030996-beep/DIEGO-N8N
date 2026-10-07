// Servidor de prueba que imita los webhooks: GET /webhook/auditoria-mov, POST /webhook/auditoria-mov-api y GET /webhook/auditoria-mov-foto
const http = require('http');
const { pedir, foto, nodo } = require('./nodos.js');
http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  if (u.pathname === '/webhook/auditoria-mov-foto') {
    const f = foto(u.searchParams.get('k') || '', u.searchParams.get('id') || '');
    if (f.json.falta) { res.writeHead(404); return res.end('no'); }
    res.writeHead(200, { 'Content-Type': 'image/jpeg' }); return res.end(Buffer.from(f.binary.data.data, 'base64'));
  }
  if (req.method === 'GET') { res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); return res.end(nodo('Mostrar página').parameters.responseBody); }
  let b = ''; req.on('data', d => b += d); req.on('end', () => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(pedir(JSON.parse(b || '{}'))));
  });
}).listen(5683, () => console.log('listo'));
