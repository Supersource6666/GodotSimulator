# 铁路场景预览

本地场景按 `scenes/urban/`（市区内）与 `scenes/outdoors/`（郊外）组织；`app/` 负责场景发现和选择，`shared/` 存放公共组件。新增模块只需添加入口和 `scene.cfg`，详见 [场景模块说明](scenes/README.md)。原有 City/Countryside 和中文启动别名继续支持。

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

`-Local` 现在先显示"市区内 / 郊外"选择界面：市区内为东京—品川，郊外为大糸线大町。
也可以跳过选择界面直接启动：

```powershell
.\run-preview.ps1 -Local -LocalScene urban
.\run-preview.ps1 -Local -LocalScene outdoors
# 中文参数同样支持：-LocalScene 市区内 / -LocalScene 郊外
```

郊外默认启用轨道、第三人称视角，速度 20 m/s（72 km/h），等效于原外部场景的启动参数。
原场景、脚本、GLB、着色器及数据包均从 `E:/game_project` 读取，不复制或重新导入到当前项目。
其中数据包为 `train/data/offline_oito_omachi`；外部目录移动后可用
`-ExternalProject '新的项目根目录'` 指定。运行期间需要保持原目录可访问。
适配器只在内存中映射资源路径；原预览已禁用的列车物理控制脚本以空脚本替代，避免依赖外部项目单例。
郊外沿用原操作：`M` 切换视角，按住 `P` 暂停，`+/-` 调速，`W` 线框；`-Cab` 可从驾驶视角启动。

验证启动入口：`.\run-preview.ps1 -Local -LocalScene outdoors -SmokeTest`。
不指定 `-LocalScene` 的 `-Local -SmokeTest` 默认验证市区内，以免自动测试停在选择界面。
默认引擎路径为 `E:/Godot_v4.7/Godot_v4.7-stable_win64_console.exe`，可通过 `-GodotPath` 覆盖。

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

## 列车调度台

选择本地场景后，会先进入"列车调度台"（参考 Libre TrainSim 的"选线路 → 编车次/时刻表 → 载入场景"流程），确认发车后才加载三维场景：

- 左侧配置运行参数：种别（のぞみ / ひかり / こだま…）、车次、编组、方向、出发时刻、最高速度。
- 中间是车站时刻表：到点 / 发点 / 停车-通过 / 停靠时分 / 股道，下方是列车运行图（时间—里程图）。
- 右侧是运行概要、前置检查与调度日志。
- 确认发车后，方案写入 `DispatchContext` 单例，再载入对应模块；三维场景按同一份方案运行——按限速走行、到站停车、通过站不停车，并显示车内调度时刻表 HUD（`T` 切换）。

常用参数：

```powershell
.\run-preview.ps1 -LocalScene urban -TrainNumber 301 -Departure 06:00   # 指定车次与发车时刻
.\run-preview.ps1 -LocalScene urban -SkipDispatch                        # 跳过调度台直接进场景
.\run-preview.ps1 -LocalScene urban -PlanFile .\plan.json                # 使用现成方案文件
.\run-preview.ps1 -DispatchTest                                          # 调度台冒烟测试（无头）
```

车站里程、种别、方向、股道等由各模块的 `dispatch.json` 提供（`scene.cfg` 中用 `dispatch="dispatch.json"` 声明）。未提供车站数据的模块按"仅限速调度"运行，例如郊外大糸线只把限速传给外部场景，不执行停站。

## 启动与操作

默认运行项目或执行 `.\run-preview.ps1` 均进入本地场景选择页；选中场景后先进入列车调度台，确认发车才加载三维场景。`-Local` 保留为兼容参数，可省略：

```powershell
.\run-preview.ps1 -LocalScene urban
.\run-preview.ps1 -LocalScene outdoors
.\run-preview.ps1 -LocalScene urban -SmokeTest
.\run-preview.ps1 -LocalScene outdoors -SmokeTest
```

`-GodotPath` 指定引擎；`-ExternalProject` 指定郊外资源根目录；`-Cab` 从驾驶视角启动；`-Loop` 开启市区循环运行；`-SkipDispatch` 跳过调度台直接进场景；`-DispatchTest` 运行调度台冒烟测试；`-TrainNumber`/`-Departure`/`-PlanFile` 见上文调度台说明。冒烟测试会自动跳过调度台，不影响原有验证流程。

市区内操作：`Space` 暂停/继续，`R` 重置，`1/2/3/4/5` 切换跟踪/俯视/瞭望/驾驶室/轮对视角，`W` 切换线框，`T` 切换调度时刻表 HUD，`Ctrl+Shift+F/G` 切换小地图/信息面板。

项目使用 Godot 内置 3D、GLTF 与物理查询功能。运行不需要额外原生扩展。
