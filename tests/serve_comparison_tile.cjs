const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../tile_diagnostic');
const server = http.createServer((req,res) => {
  const allowed = ['/tileset.json','/original.glb','/coarse/tileset.json','/coarse/original.glb'];
  const name = allowed.includes(req.url) ? req.url.slice(1) : null;
  if (!name) { res.writeHead(404).end(); return; }
  const data = fs.readFileSync(path.join(root,name));
  res.writeHead(200,{'Content-Length':data.length,'Content-Type':name.endsWith('json')?'application/json':'model/gltf-binary'});
  res.end(data);
});
server.listen(18789,'127.0.0.1',()=>console.log('COMPARISON_SERVER_READY'));
setTimeout(()=>server.close(),180000);
