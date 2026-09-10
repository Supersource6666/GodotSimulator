import json, struct, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent / '_vendor'))
import DracoPy
b = Path('offline_data/sources/sample.b3dm').read_bytes()
lengths = struct.unpack_from('<6I', b, 4)
offset = 28 + sum(lengths[2:])
g = b[offset:]
n = struct.unpack_from('<I', g, 12)[0]
j = json.loads(g[20:20+n])
binary = g[28+n:]
print('extensions', j.get('extensions'))
print('batch fields', list(json.loads(b[28+lengths[2]+lengths[3]:28+sum(lengths[2:5])]))[:30])
for p in j['meshes'][0]['primitives']:
    d = p['extensions']['KHR_draco_mesh_compression']
    v = j['bufferViews'][d['bufferView']]
    m = DracoPy.decode(binary[v.get('byteOffset', 0):v.get('byteOffset', 0)+v['byteLength']])
    print('primitive', d, 'attributes', [(a.keys(), a.get('unique_id'), a.get('data').shape) for a in m.attributes])
    print('api', [x for x in dir(m) if not x.startswith('_')])
    print('range', m.points.min(0), m.points.max(0), 'faces', m.faces.shape)
