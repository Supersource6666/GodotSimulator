"""Build an offline Tokyo-Shinagawa corridor. Network is used ONLY by this tool.
Sources: MLIT PLATEAU (buildings), GSI (DEM + aerial + geoid). No Google assets.
Run: python tools/offline_pack.py plan|build|verify
Dependencies: numpy, Pillow, DracoPy (in tools/_vendor or installed).
"""
import argparse
import concurrent.futures as futures
import copy
import hashlib
import io
import json
import math
import os
from pathlib import Path
import ssl
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "offline_data"
SRC = OUT / "sources"
MODELS = OUT / "models"
sys.path.insert(0, str(Path(__file__).parent / "_vendor"))
R = 6378137.0
E2 = 6.69437999014e-3
BUFFER = 500.0
WARDS = ("13101", "13102", "13103", "13109")
ROUTE = json.loads((ROOT / "assets/route/tokyo_shinagawa_track.json").read_text("utf-8"))["points"]
LAT0, LON0 = ROUTE[0]["lat"], ROUTE[0]["lon"]
LAT_R, LON_R = math.radians(LAT0), math.radians(LON0)
# East, up, south: a right-handed Godot/glTF Y-up local coordinate frame.
ENU = np.array([[-math.sin(LON_R), math.cos(LON_R), 0],
                [math.cos(LAT_R)*math.cos(LON_R), math.cos(LAT_R)*math.sin(LON_R), math.sin(LAT_R)],
                [math.sin(LAT_R)*math.cos(LON_R), math.sin(LAT_R)*math.sin(LON_R), -math.cos(LAT_R)]])
Y_TO_Z = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], dtype=float)
SSL = ssl.create_default_context(cafile=str(ROOT / "addons/cesium_godot/resources/cacert.pem"))

def save_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".part")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), "utf-8")
    tmp.replace(path)

def fetch(url, path, optional=False):
    if path.exists() and path.stat().st_size:
        return path.read_bytes()
    path.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "TokyoRailOfflinePreview/1.0"})
            with urllib.request.urlopen(req, context=SSL, timeout=45) as response:
                data = response.read()
                length = response.headers.get("Content-Length")
                if length and len(data) != int(length):
                    raise IOError("Incomplete response")
            tmp = path.with_suffix(path.suffix + ".part")
            tmp.write_bytes(data)
            tmp.replace(path)
            return data
        except urllib.error.HTTPError as err:
            if optional and err.code == 404:
                return None
            if err.code not in (408, 429, 500, 502, 503, 504):
                raise
        except (OSError, TimeoutError):
            if attempt == 3:
                raise
        time.sleep(1 + attempt * 2)
    raise RuntimeError("Download failed: " + str(path))

def ecef(lat, lon, height):
    lat, lon = np.radians(lat), np.radians(lon)
    n = R / np.sqrt(1 - E2 * np.sin(lat)**2)
    return np.stack(((n+height)*np.cos(lat)*np.cos(lon),
                     (n+height)*np.cos(lat)*np.sin(lon),
                     (n*(1-E2)+height)*np.sin(lat)), axis=-1)

ORIGIN = ecef(LAT0, LON0, 0.0)

def local(lat, lon, height=0.0):
    return (ecef(lat, lon, height) - ORIGIN) @ ENU.T

TRACK_XZ = np.array([local(p["lat"], p["lon"])[[0, 2]] for p in ROUTE])

def route_distance(points):
    points = np.atleast_2d(points)
    a, d = TRACK_XZ[:-1], np.diff(TRACK_XZ, axis=0)
    best = np.full(len(points), np.inf)
    for start in range(0, len(points), 1024):
        p = points[start:start+1024]
        t = np.clip(np.sum((p[:, None, :] - a) * d, axis=2) / np.sum(d*d, axis=1), 0, 1)
        best[start:start+len(p)] = np.sqrt(np.min(np.sum((p[:, None, :] - a - t[:, :, None]*d)**2, axis=2), axis=1))
    return best

def region_intersects(region):
    w, s, e, n = np.degrees(region[:4])
    corners = local(np.array([s, s, n, n]), np.array([w, e, w, e]))[:, [0, 2]]
    center = corners.mean(0)
    radius = np.linalg.norm(corners-center, axis=1).max()
    return route_distance(center)[0] <= BUFFER + radius

def tile_xy(lat, lon, z):
    scale = 2**z
    return (lon+180)/360*scale, (1-np.arcsinh(np.tan(np.radians(lat)))/np.pi)/2*scale

def tile_ll(x, y, z):
    scale = 2**z
    return np.degrees(np.arctan(np.sinh(np.pi*(1-2*np.asarray(y)/scale)))), np.asarray(x)/scale*360-180

def ground_tiles():
    xy = np.array([tile_xy(p["lat"], p["lon"], 16) for p in ROUTE])
    result = []
    for x in range(math.floor(xy[:, 0].min())-2, math.floor(xy[:, 0].max())+3):
        for y in range(math.floor(xy[:, 1].min())-2, math.floor(xy[:, 1].max())+3):
            south, west = tile_ll(x, y+1, 16)
            north, east = tile_ll(x+1, y, 16)
            if region_intersects(np.radians([west, south, east, north])):
                result.append([x, y])
    return result

def plan():
    items = []
    for ward in WARDS:
        url = f"https://api.plateauview.mlit.go.jp/datacatalog/3dtiles/{ward}-bldg-lod2-latest/tileset.json"
        def catalog(u):
            name = hashlib.sha256(u.encode()).hexdigest()[:24] + ".json"
            return json.loads(fetch(u, SRC / "catalogs" / name))
        def walk(node, base, transform):
            region = node.get("boundingVolume", {}).get("region")
            if region is None:
                raise ValueError("Unsupported catalog volume (must verify before extending)")
            if not region_intersects(region):
                return
            transform = transform @ np.array(node.get("transform", np.eye(4).T.ravel())).reshape(4, 4).T
            children = node.get("children", [])
            content = node.get("content", {})
            uri = content.get("uri", content.get("url", ""))
            if uri.endswith(".json"):
                u = urllib.parse.urljoin(base, uri)
                walk(catalog(u)["root"], u, transform)
            elif children:
                if node.get("refine") == "ADD" and uri:
                    raise ValueError("ADD content requires separate handling")
                for child in children:
                    walk(child, base, transform)
            elif uri:
                if float(node.get("geometricError", 0)) != 0:
                    raise ValueError("Leaf is not finest resolution")
                u = urllib.parse.urljoin(base, uri)
                if not u.endswith(".b3dm"):
                    raise ValueError("Unexpected content: " + u)
                key = ward + "_" + Path(urllib.parse.urlsplit(u).path).stem
                items.append({"id": key, "url": u, "region": region, "transform": transform.tolist()})
        before = len(items)
        walk(catalog(url)["root"], url, np.eye(4))
        print("PLAN ward", ward, "finest tiles", len(items)-before, flush=True)
    data = {"buffer_m": BUFFER, "buildings": items, "ground": ground_tiles()}
    save_json(OUT / "plan.json", data)
    print("PLAN total", len(items), "buildings;", len(data["ground"]), "ground chunks;",
          len(data["ground"])*16, "aerial tiles", flush=True)
    return data

class Glb:
    def __init__(self):
        self.data = bytearray()
        self.j = {"asset": {"version": "2.0", "generator": "Tokyo offline corridor builder"},
                  "buffers": [], "bufferViews": [], "accessors": [], "meshes": [],
                  "nodes": [], "scenes": [{"nodes": []}], "scene": 0}
    def view(self, data):
        while len(self.data) % 4:
            self.data.append(0)
        index = len(self.j["bufferViews"])
        self.j["bufferViews"].append({"buffer": 0, "byteOffset": len(self.data), "byteLength": len(data)})
        self.data.extend(data)
        return index
    def accessor(self, data, kind, integer=False):
        data = np.asarray(data, dtype="<u4" if integer else "<f4")

        if kind == "SCALAR":
            data = data.reshape(-1)

        index = len(self.j["accessors"])
        item = {
            "bufferView": self.view(data.tobytes()),
            "componentType": 5125 if integer else 5126,
            "count": len(data),
            "type": kind,
        }
        if kind == "VEC3":
            item.update(min=data.min(0).tolist(), max=data.max(0).tolist())

        self.j["accessors"].append(item)
        return index
    def write(self, path):
        while len(self.data) % 4:
            self.data.append(0)
        self.j["buffers"] = [{"byteLength": len(self.data)}]
        j = json.dumps(self.j, separators=(",", ":")).encode()
        j += b" " * (-len(j) % 4)
        b = struct.pack("<4sII", b"glTF", 2, 28+len(j)+len(self.data))
        b += struct.pack("<I4s", len(j), b"JSON") + j
        b += struct.pack("<I4s", len(self.data), b"BIN\0") + self.data
        path.parent.mkdir(parents=True, exist_ok=True)
        # Do not invalidate Godot imports when a resumable build yields exactly
        # the same geometry/materials. Never overwrite while editor is importing.
        if not path.exists() or path.read_bytes() != b:
            path.write_bytes(b)

def unpack_b3dm(b):
    magic, version, length, fj, fb, bj, bb = struct.unpack_from("<4s6I", b)
    assert magic == b"b3dm" and version == 1 and length == len(b)
    feature = json.loads(b[28:28+fj]) if fj else {}
    off = 28+fj+fb+bj+bb
    g = b[off:]
    magic, version, length = struct.unpack_from("<4sII", g)
    assert magic == b"glTF" and version == 2
    n, tag = struct.unpack_from("<I4s", g, 12)
    assert tag == b"JSON"
    j = json.loads(g[20:20+n])
    bn, tag = struct.unpack_from("<I4s", g, 20+n)
    assert tag == b"BIN\0"
    return feature, j, g[28+n:28+n+bn]

def convert_building(item):
    import DracoPy
    b = fetch(item["url"], SRC / "buildings" / (item["id"] + ".b3dm"))
    ft, source, binary = unpack_b3dm(b)
    # Current PLATEAU export has a single identity glTF node, ECEF-relative
    # positions in Y-up and an ECEF CESIUM_RTC center. Fail closed on variants.
    assert len(source["nodes"]) == 1 and source["nodes"][0] == {"mesh": 0}, source["nodes"]
    assert len(source["meshes"]) == 1
    center = np.array(source.get("extensions", {}).get("CESIUM_RTC", {}).get("center", [0, 0, 0]))
    center += np.array(ft.get("RTC_CENTER", [0, 0, 0]))
    tx = np.array(item["transform"])
    center = (tx @ np.append(center, 1))[:3]
    rotation = ENU @ tx[:3, :3] @ Y_TO_Z
    translation = (center-ORIGIN) @ ENU.T
    g = Glb()
    g.j["materials"] = copy.deepcopy(source.get("materials", []))
    images = []
    for image in source.get("images", []):
        view = source["bufferViews"][image["bufferView"]]
        raw = binary[view.get("byteOffset", 0):view.get("byteOffset", 0)+view["byteLength"]]
        # Preserve original pixel dimensions; avoid PNG inflation for opaque
        # photographic textures. Keep alpha-bearing images lossless.
        picture = Image.open(io.BytesIO(raw))
        encoded = io.BytesIO()
        has_alpha = "A" in picture.getbands() and picture.getchannel("A").getextrema()[0] < 255
        if has_alpha:
            picture.save(encoded, format="PNG")
        else:
            picture.convert("RGB").save(encoded, format="JPEG", quality=92)
        images.append({"bufferView": g.view(encoded.getvalue()), "mimeType": "image/png" if has_alpha else "image/jpeg"})
    if images:
        g.j["images"] = images
        g.j["textures"] = [{"source": t.get("source", t.get("extensions", {}).get("EXT_texture_webp", {}).get("source")),
                            "sampler": 0} for t in source["textures"]]
        g.j["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}]
    primitives, all_positions = [], []
    for primitive in source["meshes"][0]["primitives"]:
        extension = primitive["extensions"]["KHR_draco_mesh_compression"]
        view = source["bufferViews"][extension["bufferView"]]
        decoded = DracoPy.decode(binary[view.get("byteOffset", 0):view.get("byteOffset", 0)+view["byteLength"]])
        attrs = {name: decoded.get_attribute_by_unique_id(uid)["data"]
                 for name, uid in extension["attributes"].items()}
        p = np.asarray(attrs["POSITION"], dtype=float) @ rotation.T + translation
        assert np.all(np.isfinite(p)) and np.abs(p).max() < 20000
        faces = decoded.faces
        # Retain whole features crossing the corridor boundary, not cut walls.
        if "_BATCHID" in attrs:
            ids = attrs["_BATCHID"].reshape(-1)
            keep_ids = []
            for identifier in np.unique(ids):
                points = p[ids == identifier][:, [0, 2]]
                c = points.mean(0)
                radius = np.linalg.norm(points-c, axis=1).max()
                if route_distance(c)[0] <= BUFFER + radius:
                    keep_ids.append(identifier)
            faces = faces[np.isin(ids[faces[:, 0]], keep_ids)]
        if not len(faces):
            continue
        used, inverse = np.unique(faces, return_inverse=True)
        p = p[used]
        all_positions.append(p)
        out = {"attributes": {"POSITION": g.accessor(p, "VEC3")},
               "indices": g.accessor(inverse.astype(np.uint32).reshape(-1), "SCALAR", True),
               "material": primitive.get("material", 0)}
        for name in ("NORMAL", "TEXCOORD_0", "COLOR_0"):
            if name in attrs:
                a = np.asarray(attrs[name][used], dtype=float)
                if name == "NORMAL":
                    a = a @ np.linalg.inv(rotation)
                    a /= np.maximum(np.linalg.norm(a, axis=1, keepdims=True), 1e-12)
                elif name == "COLOR_0" and np.issubdtype(attrs[name].dtype, np.integer):
                    a /= np.iinfo(attrs[name].dtype).max
                out["attributes"][name] = g.accessor(a, "VEC"+str(a.shape[1]))
        primitives.append(out)
    if not primitives:
        return None
    g.j["meshes"] = [{"primitives": primitives}]
    g.j["nodes"] = [{"mesh": 0}]
    g.j["scenes"][0]["nodes"] = [0]
    path = MODELS / (item["id"] + ".glb")
    g.write(path)
    points = np.concatenate(all_positions)
    return {"path": path.relative_to(ROOT).as_posix(), "kind": "buildings",
            "min": points.min(0).tolist(), "max": points.max(0).tolist(),
            "vertices": len(points), "source_id": item["id"]}

DEM_CACHE = {}
GEOID = None
VOID_SAMPLES = 0
VOID_MAX_DISTANCE = 0.0

def geoid(lat, lon):
    global GEOID
    if GEOID is None:
        values = []
        for point in (ROUTE[0], ROUTE[len(ROUTE)//2], ROUTE[-1]):
            la, lo = point["lat"], point["lon"]
            u = ("https://vldb.gsi.go.jp/sokuchi/surveycalc/geoid/calcgh/cgi/geoidcalc.pl"
                 f"?outputType=json&latitude={la}&longitude={lo}")
            name = f"geoid_{la}_{lo}.json"
            j = json.loads(fetch(u, SRC / name))["OutputData"]
            values.append([la, float(j["geoidHeight"])])
        GEOID = sorted(values)
    return np.interp(lat, [v[0] for v in GEOID], [v[1] for v in GEOID])

def dem_array(layer, z, x, y):
    key = layer, z, x, y
    if key not in DEM_CACHE:
        u = f"https://cyberjapandata.gsi.go.jp/xyz/{layer}/{z}/{x}/{y}.png"
        b = fetch(u, SRC / "gsi" / layer / str(z) / str(x) / f"{y}.png", optional=True)
        if b is None:
            DEM_CACHE[key] = np.full((256, 256), np.nan)
        else:
            c = np.array(Image.open(io.BytesIO(b)).convert("RGB"), dtype=np.int32)
            value = c[:, :, 0]*65536+c[:, :, 1]*256+c[:, :, 2]
            DEM_CACHE[key] = np.where(value == 8388608, np.nan,
                                      np.where(value > 8388608, value-16777216, value)*0.01)
    return DEM_CACHE[key]

def height(lat, lon, fill_small_voids=False):
    lat, lon = np.broadcast_arrays(lat, lon)
    result = np.full(lat.shape, np.nan)
    # Bilinear sample across tile boundaries. Fill only missing samples from
    # coarser official DEM; never silently synthesize zero-height land.
    for layer, z in (("dem5a_png", 15), ("dem5b_png", 15), ("dem5c_png", 15), ("dem_png", 14)):
        if np.all(np.isfinite(result)):
            break
        xx, yy = tile_xy(lat, lon, z)
        px, py = np.asarray(xx*256), np.asarray(yy*256)
        ix, iy = np.floor(px).astype(int), np.floor(py).astype(int)
        values = []
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            ax, ay = ix+dx, iy+dy
            v = np.full(lat.shape, np.nan)
            pairs = np.unique(np.stack([ax.ravel()//256, ay.ravel()//256], axis=1), axis=0)
            for tx, ty in pairs:
                mask = (ax//256 == tx) & (ay//256 == ty) & ~np.isfinite(result)
                if mask.any():
                    v[mask] = dem_array(layer, z, int(tx), int(ty))[ay[mask]%256, ax[mask]%256]
            values.append(v)
        fx, fy = px-ix, py-iy
        sample = values[0]*(1-fx)*(1-fy)+values[1]*fx*(1-fy)+values[2]*(1-fx)*fy+values[3]*fx*fy
        mask = ~np.isfinite(result)
        result[mask] = sample[mask]
    if not np.all(np.isfinite(result)):
        missing = ~np.isfinite(result)
        print("DEM missing samples", int(missing.sum()), "lat", float(lat[missing].min()),
              float(lat[missing].max()), "lon", float(lon[missing].min()), float(lon[missing].max()), flush=True)
        if not fill_small_voids or not np.any(~missing):
            raise ValueError("DEM nodata remains on route: cannot certify height")
        # Small DEM voids (often water) are explicitly recorded interpolation,
        # not claimed as surveyed elevation. Never use this for track samples.
        global VOID_SAMPLES, VOID_MAX_DISTANCE
        xy = local(lat, lon)[:, [0, 2]]
        valid_xy, valid_h = xy[~missing], result[~missing]
        for index in np.flatnonzero(missing):
            d = np.linalg.norm(valid_xy - xy[index], axis=1)
            nearest = np.argsort(d)[:4]
            if d[nearest[0]] > 250:
                raise ValueError("DEM void exceeds 250 m interpolation limit")
            w = 1 / np.maximum(d[nearest], 0.01)**2
            result[index] = np.sum(valid_h[nearest]*w)/w.sum()
            VOID_MAX_DISTANCE = max(VOID_MAX_DISTANCE, float(d[nearest[0]]))
        VOID_SAMPLES += int(missing.sum())
    return result

def build_ground(x, y):
    picture = Image.new("RGB", (1024, 1024))
    def get_tile(pair):
        dx, dy = pair
        tx, ty = x*4+dx, y*4+dy
        url = f"https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/18/{tx}/{ty}.jpg"
        data = fetch(url, SRC / "gsi/seamlessphoto/18" / str(tx) / f"{ty}.jpg")
        image = Image.open(io.BytesIO(data)).convert("RGB")
        assert image.size == (256, 256)
        return dx, dy, image
    with futures.ThreadPoolExecutor(max_workers=4) as pool:
        for dx, dy, image in pool.map(get_tile, [(i, j) for j in range(4) for i in range(4)]):
            picture.paste(image, (dx*256, dy*256))
    uv = np.stack(np.meshgrid(np.linspace(0, 1, 65), np.linspace(0, 1, 65)), axis=-1).reshape(-1, 2)
    lat, lon = tile_ll(x+uv[:, 0], y+uv[:, 1], 16)
    # Clip geometry, not just tile centers: edge tiles can extend far into
    # Tokyo Bay where land DEM correctly has no elevation. One grid-cell
    # guard band preserves continuous coverage at the 500 m boundary.
    inside = route_distance(local(lat, lon)[:, [0, 2]]) <= BUFFER + 15
    h = np.zeros(len(lat))
    if not inside.any():
        return None
    h[inside] = height(lat[inside], lon[inside], fill_small_voids=True)
    p = local(lat, lon, h+geoid(lat, lon))
    faces = []
    for row in range(64):
        for col in range(64):
            a = row*65+col
            faces.extend((a, a+65, a+1, a+1, a+65, a+66))
    faces = np.asarray(faces).reshape(-1, 3)
    faces = faces[np.all(inside[faces], axis=1)]
    if not len(faces):
        return None
    used, faces = np.unique(faces, return_inverse=True)
    p, uv = p[used], uv[used]
    g = Glb()
    encoded = io.BytesIO()
    picture.save(encoded, format="JPEG", quality=94)
    g.j["images"] = [{"bufferView": g.view(encoded.getvalue()), "mimeType": "image/jpeg"}]
    g.j["textures"] = [{"source": 0, "sampler": 0}]
    g.j["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}]
    g.j["materials"] = [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0},
                                                "metallicFactor": 0, "roughnessFactor": 1}}]
    g.j["meshes"] = [{"primitives": [{"attributes": {"POSITION": g.accessor(p, "VEC3"),
                                                    "TEXCOORD_0": g.accessor(uv, "VEC2")},
                                      "indices": g.accessor(faces, "SCALAR", True), "material": 0}]}]
    g.j["nodes"] = [{"mesh": 0}]
    g.j["scenes"][0]["nodes"] = [0]
    path = MODELS / f"ground_{x}_{y}.glb"
    g.write(path)
    return {"path": path.relative_to(ROOT).as_posix(), "kind": "ground",
            "min": p.min(0).tolist(), "max": p.max(0).tolist(), "vertices": len(p)}

def build():
    save_json(OUT / "manifest.json", {"version": 1, "complete": False, "status": "building"})
    data = json.loads((OUT / "plan.json").read_text("utf-8")) if (OUT / "plan.json").exists() else plan()
    items = []
    # Moderate concurrency, resumable source files. Rebuild output deterministically.
    with futures.ThreadPoolExecutor(max_workers=4) as pool:
        for i, result in enumerate(pool.map(convert_building, data["buildings"])):
            if result:
                items.append(result)
            if (i+1) % 10 == 0:
                print("BUILD buildings", i+1, "/", len(data["buildings"]), flush=True)
    for i, (x, y) in enumerate(data["ground"]):
        result = build_ground(x, y)
        if result:
            items.append(result)
        print("BUILD ground", i+1, "/", len(data["ground"]), flush=True)
    lat = np.array([p["lat"] for p in ROUTE])
    lon = np.array([p["lon"] for p in ROUTE])
    ground = height(lat, lon)
    # Visual rail elevation, NOT a surveyed track vertical profile. Smooth it
    # to prevent DEM noise from jolting train/camera; preserve the real XY route.
    rail = ground + 6.0
    for _ in range(3):
        rail[1:-1] = (rail[:-2]+2*rail[1:-1]+rail[2:])/4
    route = local(lat, lon, rail+geoid(lat, lon)).tolist()
    for item in items:
        path = ROOT / item["path"]
        item.update(bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    manifest = {"version": 1, "complete": True, "buffer_m": BUFFER, "origin": [LAT0, LON0, 0],
                "route": route, "ground_heights_m": ground.tolist(), "geoid_samples": GEOID,
                "dem_void_interpolated_samples": VOID_SAMPLES, "dem_void_max_distance_m": VOID_MAX_DISTANCE,
                "vertical_profile": "GSI DEM + interpolated GSI geoid; visual rail = smoothed DEM + 6 m (not surveyed)",
                "assets": items, "sources": ["MLIT PLATEAU", "GSI seamlessphoto / DEM", "OpenStreetMap contributors"],
                "imagery_zoom": 18, "built_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    save_json(OUT / "manifest.json", manifest)
    verify()

def verify():
    j = json.loads((OUT / "manifest.json").read_text("utf-8"))
    assert j["complete"] and j["version"] == 1 and len(j["route"]) == len(ROUTE)
    total = 0
    for item in j["assets"]:
        rel = Path(item["path"])
        assert not rel.is_absolute() and ".." not in rel.parts and rel.parts[:2] == ("offline_data", "models")
        p = ROOT / rel
        assert p.is_file() and p.stat().st_size == item["bytes"], p
        assert hashlib.sha256(p.read_bytes()).hexdigest() == item["sha256"], p
        b = p.read_bytes()
        n = struct.unpack_from("<I", b, 12)[0]
        g = json.loads(b[20:20+n])
        assert all("uri" not in v for v in g.get("buffers", [])+g.get("images", []))
        assert not g.get("extensionsRequired")
        total += len(b)
    print("OFFLINE_VERIFY PASS assets", len(j["assets"]), "bytes", total, "route_points", len(j["route"]), flush=True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["plan", "build", "verify"])
    args = parser.parse_args()
    {"plan": plan, "build": build, "verify": verify}[args.action]()
