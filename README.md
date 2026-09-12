# 东京—品川站间地形预览

## 本地加载版本（不需要网络和 Token）

跟踪相机默认位于轨道前方 100 m、轨面上方 40 m；建筑挡住机位或列车时先拉近、再升高。
平滑过渡也检查碰撞。封闭站棚遮住整列车而没有安全视野时会暂停（当前品川站约 6.33 km 后存在此情况）。

本地包采用 PLATEAU 建筑 + 国土地理院航空影像/高程，覆盖现有东京—品川轨道约 6.7 km、两侧各 500 m。
不使用 Google 瓦片。相机沿同一轨道线路跟随用户列车模型；全部本地资源加载后才开始前进。

左上角小地图始终显示本地线路、列车方向和实时经纬度。需要 Google Maps 底图时，
请在 Google Cloud 中启用 Maps Static API 和结算，将 API Key 单独写入项目根目录的
`google_maps_api_key.txt`。该文件已加入 `.gitignore`，不会上传 GitHub；未配置 Key 或
网络不可用时，小地图自动保留为本地线路模式。为减少地图请求，每 500 m 才更新一次底图，
同一运行会话内会复用已下载的地图。

```powershell
cd E:\GodotSimulator
powershell -ExecutionPolicy Bypass -File .\run-preview.ps1 -Local
```

首次制作、下载中断后续传或重新导入资源：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-offline.ps1
powershell -ExecutionPolicy Bypass -File .\build-offline.ps1 -VerifyOnly
```

构建依赖 Python 3.11、numpy、Pillow、DracoPy 1.7.0（项目 tools/_vendor）。
运行只需要 Godot 和本地资源；拷贝到另一机器后需先用 Godot 导入一次。
原始数据在 offline_data/sources，自包含模型在 offline_data/models，完整性清单为 offline_data/manifest.json。
显存预设：摄影贴图上限 2048、显存压缩、mipmap；保留原始下载文件和原像素尺寸 GLB，建筑不自动简化。
无运行时网络等待和多瓦片三角形检测，但启动时仍需本地资源加载，性能取决于显卡、内存和磁盘。

注意：这是航空影像 + 城市建筑模型，不等同 Google 摄影测量，也不补造树木、车辆或站台。
轨道高度为平滑 DEM + 6 m 的视觉估计，不是实测铁路纵断面。
数据来源、加工与高程缺测处理见 [offline_data/ATTRIBUTION.md](offline_data/ATTRIBUTION.md)。

以下为原在线模式说明；不加 `-Local` 仍启动在线模式。

本工程使用 Cesium for Godot，仅预览东海道新干线的第一个站间段：

东京站 → 品川站

时间压缩固定为 1×，参考东海道新干线最高运营速度 285 km/h。东京附近地形完成初始加载后自动发车，到达品川后停止。

## 地形数据

项目根目录的 `cesium_token.txt` 需要包含有效 Cesium ion Token。默认加载 Google Photorealistic 3D Tiles（资产 2275207），用于带建筑立面、树木等纹理的实景三维效果。需要该资产的访问权限，并能连接 Cesium ion 和 Google 瓦片服务；没有收到瓦片时会留在起点等待，不会自动换成航拍地形。

使用 `-- --terrain-preview` 启动参数可切回 World Terrain（1）+ Bing Aerial（2）+ PLATEAU（2602291）。此模式不等同于完整实景三维，不能仅靠提高 SSE 精度获得车辆、植被的摄影测量细节。

## 操作

### 磁盘缓存与检测性能

已修复真实 HTTP 响应头透传，SQLite 按服务端的 Cache-Control、ETag、
Last-Modified 等规则复用或重新验证资源，不强行缓存 no-store、不修改过期时间。
缓存位置为 %APPDATA%/Godot/app_userdata/Tokyo-Shinagawa Terrain Preview/cache。
这是运行缓存，不是东京—品川全段的永久离线包；首次访问的新区域仍需要联网。
更新原生 DLL 后请完全退出并重新启动 Godot。

原生瓦片的三角形查询加速结构在后台加载阶段预构建；
未预构建模型采用每帧最多一个的兜底队列，检测和轨面贴合共享缓存，
网格变更时失效、卸载后清理。缺少查询结构时保持暂停，不降低近景门槛。
单个特别大的兜底模型仍可能超过帧预算。

验证：python tests/cache_inventory.py
仅输出缓存数量与容量，不输出签名 URL。

Windows 推荐执行 `powershell -File .\run-preview.ps1`。启动器会将已经配置的系统代理传给插件的 libcurl 下载器，不修改系统代理设置。`-Terrain` 切回航拍地形模式，`-SmokeTest` 执行 30 秒无界面加载测试，`-GodotPath` 指定其他引擎路径，`-Cab` 可直接从驾驶室视角启动。直接调用 Godot 时也可在 `--` 后传入 `--cab-view`。直接从未继承代理环境的编辑器运行，Google 数据可能无法下载。

- `Space`：暂停/继续
- `R`：重新预览东京到品川
- `C`：在轨道跟车视角与驾驶室司机视角之间切换；司机视角位于头车驾驶位高度，使用 64° 视野

路线已改为真实轨道折线（170 个连通节点，约 6.7 km），不再连接两站中心走直线。轨道 © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright)，ODbL；离线快照及重建说明在 assets/route。该路线是可视化选线，不是行车调度数据。

列车使用 E:/game_project/train/models 中的 train1.glb，并装配两个转向架、四组轮对；复制到 assets/train 后不再依赖外部工程。相机沿同一轨道在列车后方约 85 m、轨面上方约 65 m 跟随，随弯道转向。没有实测轨道高程，当前使用椭球高 46 m 基准及 ±8 m 近景表面贴合；站棚遮挡、摄影测量偏移仍可能需要校准，不是工程级贴轨精度。

启动时对视野内 9 个位置进行带纹理三角形相交检测，只认可射线最前面的可见表面，不能用被粗模挡住的细瓦片充数。实景瓦片还必须具有 ≤8.1 m 的几何误差元数据；至少 7 个位置连续覆盖 5 秒、列车加载完成后才前进。运行中每秒复查，覆盖不足则停止等待。每前进 500 m 还会等待瓦片稳定。这是近景最低门槛，不代表最高精度 LOD，也不覆盖所有屏幕像素。

当前插件在地理参考模式下按地理原点选择瓦片，因此脚本让地理原点跟随相机，局部相机位置保持为零。`forbid_holes` 用于等待子瓦片时保留父瓦片。原生插件的资源释放警告仍需单独诊断，不能视为已经修复。

司机视角验证：`Godot --headless --path . --script res://tests/cab_view.gd`。

验证命令：`Godot --headless --path . --script res://tests/preview_configuration.gd`；数据加载测试：`Godot --headless --path . -- --demo-smoke-test`。
