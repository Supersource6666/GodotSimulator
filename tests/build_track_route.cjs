// Rebuild from the attributed Overpass snapshot, without network access.
const fs = require('fs');
const raw = JSON.parse(fs.readFileSync('assets/route/tokyo_shinagawa_osm.json', 'utf8'));
const ways = raw.elements.filter(w => w.tags?.name === '東海道新幹線' && !w.tags.service);
const nodes = new Map(), edges = new Map();
const distance = (a,b) => Math.hypot((a.lat-b.lat)*111195, (a.lon-b.lon)*90300);
for (const w of ways) for (let i=0;i<w.nodes.length;i++) {
  const id=w.nodes[i]; nodes.set(id,w.geometry[i]);
  if(!edges.has(id)) edges.set(id,[]);
  if(i) {const prev=w.nodes[i-1], cost=distance(w.geometry[i-1],w.geometry[i]);
    edges.get(id).push({id:prev,cost,way:w.id}); edges.get(prev).push({id,cost,way:w.id});}
}
const startAnchor={lat:35.6810,lon:139.7682}, endAnchor={lat:35.6285,lon:139.7400};
const start=[...nodes.keys()].sort((a,b)=>distance(nodes.get(a),startAnchor)-distance(nodes.get(b),startAnchor))[0];
const costs=new Map([[start,0]]), parents=new Map(), done=new Set();
while(true){
  const candidates=[...costs.keys()].filter(id=>!done.has(id)).sort((a,b)=>costs.get(a)-costs.get(b));
  if(!candidates.length) break;
  const id=candidates[0];done.add(id);
  for(const e of edges.get(id)) if(costs.get(id)+e.cost<(costs.get(e.id)??Infinity)) {
    costs.set(e.id,costs.get(id)+e.cost);parents.set(e.id,{id,way:e.way});
  }
}
const end=[...done].sort((a,b)=>distance(nodes.get(a),endAnchor)-distance(nodes.get(b),endAnchor))[0];
if(distance(nodes.get(end),endAnchor)>200) throw Error('No connected track to Shinagawa');
const ids=[end], wayIds=[];
while(ids.at(-1)!==start){const p=parents.get(ids.at(-1));ids.push(p.id);wayIds.push(p.way);}
ids.reverse();wayIds.reverse();
const result={source:'OpenStreetMap contributors',license:'ODbL-1.0',attribution_url:'https://www.openstreetmap.org/copyright',
  timestamp:raw.osm3s.timestamp_osm_base,way_ids:[...new Set(wayIds)],node_ids:ids,points:ids.map(id=>nodes.get(id))};
if(costs.get(end)<6000 || costs.get(end)>8000) throw Error('Unexpected route length');
fs.writeFileSync('assets/route/tokyo_shinagawa_track.json',JSON.stringify(result,null,2)+'\n');
console.log('TRACK_BUILT',ids.length,'nodes',costs.get(end),'meters',result.points[0],result.points.at(-1));
