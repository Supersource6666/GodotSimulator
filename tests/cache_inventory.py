"""Read-only cache summary. Never print signed URLs, tokens, or headers."""
import json
import os
import sqlite3
import time
from pathlib import Path
from urllib.parse import urlsplit

path = Path(os.environ["APPDATA"]) / "Godot/app_userdata/Tokyo-Shinagawa Terrain Preview/cache/cesium-request-cache.sqlite"
groups = {}
with sqlite3.connect(path.as_uri() + "?mode=ro", uri=True) as db:
    for url, length, expiry, headers in db.execute(
        "SELECT requestUrl, length(responseData), expiryTime, responseHeaders FROM CacheItemTable"
    ):
        host = urlsplit(url).hostname or ""
        group = "google" if host.endswith(".googleapis.com") else "cesium" if host.endswith(".cesium.com") else "local_test" if host == "127.0.0.1" else "other"
        stats = groups.setdefault(group, {"entries": 0, "payload_bytes": 0, "fresh": 0, "with_cache_control": 0})
        stats["entries"] += 1
        stats["payload_bytes"] += length or 0
        stats["fresh"] += int(float(expiry) >= time.time())
        stats["with_cache_control"] += int("cache-control" in {k.lower() for k in json.loads(headers)})
print(json.dumps({"database_bytes": path.stat().st_size, "groups": groups}, indent=2))
