// Actual plugin + SQLite across separate processes, using only local fixtures.
const http = require('node:http'), fs = require('node:fs'), zlib = require('node:zlib');
const {spawn} = require('node:child_process'), assert = require('node:assert/strict');
const engine = process.argv[2] || 'E:/Godot_v4.7/Godot_v4.7-stable_win64.exe';
const run = Date.now().toString(), counts = {}, validations = {};
const etag = '"cache-fixture-v1"', modified = 'Mon, 01 Sep 2025 00:00:00 GMT';
const server = http.createServer((req,res)=>{
  const [,prefix,mode,file] = req.url.split('/');
  if(prefix !== run || !['tileset.json','original.glb'].includes(file)) {res.writeHead(404).end();return;}
  const key = mode+'/'+file; counts[key]=(counts[key]||0)+1;
  if(mode === 'redirect' && file === 'tileset.json'){
    res.writeHead(302,{'Location':'/'+run+'/final/tileset.json','Cache-Control':'public, max-age=3600'}).end('redirect body must be discarded');return;
  }
  const noStore = ['no-store','redirect','final'].includes(mode);
  const revalidate = ['revalidate','modified'].includes(mode);
  const headers = {
    'cAcHe-CoNtRoL': noStore ? 'no-store' : revalidate ? 'no-cache, max-age=0' : 'public, max-age=3600',
    'Content-Type': file.endsWith('.json') ? 'application/json' : 'model/gltf-binary',
    'Last-Modified':modified
  };
  if(mode !== 'modified') headers.ETag=etag;
  if(revalidate && (req.headers['if-none-match'] === etag || req.headers['if-modified-since'] === modified)){
    validations[key]=(validations[key]||0)+1;res.writeHead(304,headers).end();return;
  }
  let data=fs.readFileSync('tile_diagnostic/'+file);
  if(mode === 'gzip'){data=zlib.gzipSync(data);headers['Content-Encoding']='gzip';}
  headers['Content-Length']=data.length;res.writeHead(200,headers).end(data);
});
async function probe(mode){
  const url='http://127.0.0.1:18791/'+run+'/'+mode+'/tileset.json';
  await new Promise((resolve,reject)=>{
    const child=spawn(engine,['--headless','--max-fps','120','--path',process.cwd(),'--script','res://tests/compare_tile.gd','--quit-after','1200','--','--cache-probe','--tileset-url='+url],{windowsHide:true});
    let output='';child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>output+=b);
    const timer=setTimeout(()=>{child.kill();reject(Error('Probe timed out: '+mode));},30000);
    child.on('error',reject);
    child.on('close',code=>{clearTimeout(timer);if(output.includes('CACHE_PROBE_PASS'))resolve();else reject(Error(mode+' failed, exit='+code+'\n'+output));});
  });
}
(async()=>{
  await new Promise(resolve=>server.listen(18791,'127.0.0.1',resolve));
  try {
    for(const mode of ['cache','no-store','revalidate','modified','redirect','gzip']){
      await probe(mode);await probe(mode);
      for(const file of ['tileset.json','original.glb']){
        const key=mode+'/'+file;
        assert.equal(counts[key],['cache','gzip'].includes(mode)?1:2,key);
        if(['revalidate','modified'].includes(mode))assert.equal(validations[key],1,'304 '+key);
      }
      if(mode==='redirect')assert.equal(counts['final/tileset.json'],2,'redirect must not leak cache policy');
      console.log('CACHE_CASE_PASS',mode);
    }
    fs.writeFileSync('tests/cache-results.json',JSON.stringify({run,counts,validations},null,2));
    console.log('CACHE_INTEGRATION_PASS');
  } finally {server.close();}
})().catch(error=>{console.error(error);process.exitCode=1;server.close();});
