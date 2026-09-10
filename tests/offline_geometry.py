"""Read-only local package geometry and corridor checks. No network calls."""
import json
import sys
import struct
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import offline_pack as pack

def glb(path):
    b = path.read_bytes()
    n = struct.unpack_from("<I", b, 12)[0]
    j = json.loads(b[20:20+n])
    binary = b[28+n:]
    def array(index):
        a = j["accessors"][index]
        v = j["bufferViews"][a["bufferView"]]
        types = {5126: "<f4", 5125: "<u4", 5123: "<u2"}
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        return np.frombuffer(binary, types[a["componentType"]], a["count"]*width,
                             v.get("byteOffset", 0)+a.get("byteOffset", 0)).reshape(-1, width)
    return j, array

pack.verify()
manifest = json.loads((pack.OUT / "manifest.json").read_text("utf-8"))
ground = []
vertices = triangles = 0
for item in manifest["assets"]:
    j, array = glb(pack.ROOT / item["path"])
    for primitive in j["meshes"][0]["primitives"]:
        points = array(primitive["attributes"]["POSITION"])
        faces = array(primitive["indices"]).reshape(-1, 3)
        assert faces.max() < len(points) and np.isfinite(points).all()
        vertices += len(points)
        triangles += len(faces)
        if item["kind"] == "ground":
            p = points[faces]
            cross = np.cross(p[:, 1]-p[:, 0], p[:, 2]-p[:, 0])
            assert (cross[:, 1] > 0).all(), "Wrong ground winding"
            tri = p[:, :, [0, 2]].astype(float)
            ground.append((points[:, [0, 2]].min(0), points[:, [0, 2]].max(0), tri))

def is_covered(point):
    for lo, hi, t in ground:
        if (point < lo).any() or (point > hi).any():
            continue
        a = t[:, 0]
        b = t[:, 1]-a
        c = t[:, 2]-a
        v = point-a
        det = b[:, 0]*c[:, 1]-b[:, 1]*c[:, 0]
        u = (v[:, 0]*c[:, 1]-v[:, 1]*c[:, 0])/det
        w = (b[:, 0]*v[:, 1]-b[:, 1]*v[:, 0])/det
        if ((u >= -1e-5) & (w >= -1e-5) & (u+w <= 1+1e-5)).any():
            return True
    return False

route = np.array(manifest["route"])[:, [0, 2]]
lengths = np.linalg.norm(np.diff(route, axis=0), axis=1)
chain = np.r_[0, np.cumsum(lengths)]
count = 0
for distance in np.r_[np.arange(0, chain[-1], 50), chain[-1]]:
    i = min(np.searchsorted(chain, distance, side="right")-1, len(lengths)-1)
    tangent = (route[i+1]-route[i])/lengths[i]
    point = route[i]+tangent*(distance-chain[i])
    perpendicular = np.array([-tangent[1], tangent[0]])
    for offset in np.arange(-500, 501, 50):
        p = point + perpendicular*offset
        assert is_covered(p), ("Ground gap", float(distance), int(offset), p.tolist())
        count += 1
result = {"pass": True, "vertices": vertices, "triangles": triangles, "corridor_samples": count,
          "sample_spacing_m": 50, "half_width_m": 500, "route_m": float(chain[-1]),
          "dem_void_samples": manifest["dem_void_interpolated_samples"]}
(pack.ROOT / "tests/offline-geometry-results.json").write_text(json.dumps(result, indent=2), "utf-8")
print("OFFLINE_GEOMETRY PASS", result)
