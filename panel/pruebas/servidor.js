// Servidor de prueba que imita los webhooks: GET /webhook/mis-ligas y POST /webhook/mis-ligas-api
const http = require('http');
const { pedir, nodo } = require('./nodos.js');
http.createServer((req, res) => {
  if (req.method === 'GET' && req.url.startsWith('/webhook/mis-ligas')) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(nodo('Mostrar página').parameters.responseBody);
  }
  let b = ''; req.on('data', d => b += d); req.on('end', () => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(pedir(JSON.parse(b || '{}'))));
  });
}).listen(5682, () => console.log('listo'));
