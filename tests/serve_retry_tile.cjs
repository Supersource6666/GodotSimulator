const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname,'../tile_diagnostic');
const counts = {};
const server = http.createServer((req,res)=>{
  counts[req.url] = (counts[req.url] || 0)+1;
  if (req.url === '/tileset.json' && counts[req.url] < 3) {
    res.writeHead(503).end('temporary'); return;
  }
  if (req.url === '/original.glb' && counts[req.url] === 1) {
    req.socket.destroy(); return;
  }
  const name = req.url === '/tileset.json' ? 'tileset.json' : req.url === '/original.glb' ? 'original.glb' : null;
  if (!name) {res.writeHead(404).end();return;}
  const data=fs.readFileSync(path.join(root,name));
  res.writeHead(200,{'Content-Length':data.length});res.end(data);
  console.log('RETRY_SERVED', name, counts[req.url]);
});
server.listen(18789,'127.0.0.1',()=>console.log('RETRY_SERVER_READY'));
setTimeout(()=>server.close(),90000);
