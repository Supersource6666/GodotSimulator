# Windows loading-chain fix

The project now loads bin/Godot3DTiles.cachefix.windows.x86_64.dll. The original
DLL is retained. Source changes are preserved in loading_chain.patch (Codex
apply_patch format, relative to the Cesium for Godot source root).
Apply visibility.patch afterwards: it explicitly hides cached tile nodes
which are absent from the current selection, including their physics shapes.
Then apply cache_and_query.patch: response headers are passed to Cesium's
cache, and query BVHs are built on the load task before scene publication when
the project setting cesium/prepare_query_meshes is enabled. Previous DLLs remain.

Current Windows DLL SHA-256:
B730DF7F1CFDBB10271FC4A6FF835FF7288E06C0F80D014D97611C611702BBB1

Built from E:/cesium_build/3D-Tiles-For-Godot with the existing local SCsub
and texture-loader changes preserved:

    python -m SCons -f SConstruct.py platform=windows arch=x86_64 compileTarget=extension target=template_release buildCesium=no -j4

Changes: exclusive curl handle per request; captured method by value;
initialized response status; cleanup on every path; worker join before client
data destruction; verified TLS using the bundled CA file; at most four GET
attempts for transient transport failures / HTTP 408, 429 and 5xx; no signed
URLs in the new transport error message. Published preview_geometric_error
metadata lets journey.gd reject coarse or unknown-detail tiles.

Controlled retry test: tests/serve_retry_tile.cjs returned HTTP 503 twice for
tileset.json, and dropped the first original.glb connection. The new DLL
loaded them on attempts 3 and 2 respectively. Same-GLB comparison still
matched vertex positions and topology. Shutdown dependency warnings remain;
these changes do not claim to fix native resource teardown.
