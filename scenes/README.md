# 场景模块
生成track_detail.png的命令是：
```powershell
E:\Godot_v4.7\Godot_v4.7-stable_win64_console.exe --path "E:\GodotSimulator" res://scenes/travel/scene.tscn -- --travel-capture --external-project=E:/game_project
```
本地场景由 `app/scene_registry.gd` 自动发现。每个模块使用独立目录和 `scene.cfg`，选择界面与启动脚本不维护场景列表。

```text
app/                      本地场景选择、模块发现与列车调度台（app/dispatch/）
scenes/
  urban/                  市区内：场景、行程控制、加载界面
  outdoors/               郊外：外部场景入口、资源读取适配器
  on_ground/              地面线路：复用 outdoors 资源，轨道随地面高度铺设
shared/                   列车、驾驶室、相机、路线、小地图等组件
assets/                   项目内共用模型和程序化轨道
GPS_Data/                 速度与位置数据
offline_data/             urban 的既有离线数据目录
```

## 新增场景

1. 新建 `scenes/<id>/`，其中 `id` 使用小写，不能与其他模块或别名重复。
2. 添加 Godot 入口场景（默认 `scene.tscn`）和该场景自己的脚本。入口节点可使用任意 Node 类型，不必继承 urban 或 outdoors。
3. 添加 `scene.cfg`，例如 `scenes/mountain/scene.cfg`：

```ini
[scene]
id="mountain"
title="山地"
description="山地线路预览"
entry="scene.tscn"
order=30
aliases=["山地"]
```

`entry` 是模块目录内的相对路径；`description`、`order`、`aliases` 可省略，默认分别为空、100、空数组。排序按 `order`，相同时按 `id`。
没有 `scene.cfg` 的目录不会出现在本地场景菜单中。入口丢失、ID 与目录不一致或别名重复会显示明确错误。

重新运行后，新模块自动出现在选择界面，也可以直接启动：

```powershell
.\run-preview.ps1 -Local -LocalScene mountain
```

启动 ID 和别名不区分大小写。urban 保留 `City`、`市区内` 别名，outdoors 保留 `Countryside`、`郊外` 别名。
默认冒烟场景由 `project.godot` 中的 `application/local_scenes/default_id` 指定，当前是 urban。默认启动（也可带 `-Local`）显示菜单，指定 `-LocalScene` 则直接进入对应模块。

## 调度配置

选中场景后，`app/dispatch/dispatch_console.tscn` 作为中转的列车调度台，确认发车后把方案写入 `DispatchContext` 单例，再载入模块场景。模块可用 `scene.cfg` 的可选键声明调度配置：

```ini
dispatch="dispatch.json"
```

`dispatch.json` 结构（`schema` 为 1）：

```json
{
  "schema": 1,
  "route": {
    "name": "东海道新干线",
    "section": "东京 → 品川",
    "operator": "JR 东海",
    "distance_m": 6689,
    "max_speed_kmh": 285,
    "directions": [{ "key": "down", "label": "下り 东京 → 品川", "simulated": true }]
  },
  "services": [{ "key": "nozomi", "name": "のぞみ", "label": "希望号", "speed_kmh": 285, "cars": 16 }],
  "stations": [
    { "name": "东京", "code": "TYO", "chainage_m": 0, "platform": "14番線", "platforms": ["14番線"], "dwell_s": 90, "origin": true }
  ]
}
```

- `route.distance_m` 为线路长度（米）；`stations[].chainage_m` 为各站里程，`dwell_s` 为停站时分。
- `stations` 为空时进入"仅限速调度"模式：只把 `max_speed_kmh` 传给模块，不生成时刻表、不执行停站。
- 模块场景自行读取 `DispatchContext.resolve()` 获取方案（参考 `scenes/urban/urban.gd` 的 `_setup_dispatch`）。
- 调度方案与运行曲线由 `app/dispatch/dispatch_plan.gd` 统一计算，调度台与三维场景共用同一份逻辑，计划与实绩一致。

## 模块边界

- 场景专属逻辑放在模块目录中；可复用组件放在 `shared/` 或 `assets/procedural/`。
- 模块自行读取所需的用户参数、创建资源，并在退出时释放注册的加载器等状态。
- `-SmokeTest` 向模块传递 `--demo-smoke-test`。支持自动验证的模块需自行检查就绪状态，然后用退出码 0 表示成功、非 0 表示失败。
- `-Cab`、`-Loop`、`-ExternalProject` 会原样传递对应用户参数，是否支持由模块决定。
- 大型数据不要求迁移到模块目录。urban 继续使用现有 `offline_data/`，outdoors 继续直接读取外部 `E:/game_project` 的场景和模型。
- 运行时通过配置字符串发现入口。未来制作导出包时，需包含各模块的 `scene.cfg` 和入口资源；外部磁盘资源仍需单独部署。

直接从 Godot 启动本地菜单可使用 `res://app/local.tscn`；两个模块的直接入口分别为 `res://scenes/urban/scene.tscn` 和 `res://scenes/outdoors/scene.tscn`。

## 地面线路 on_ground

`on_ground` 继承 outdoors 的资源加载、列车、相机与进度控制，使用同一外部项目和大糸线数据。保留线路平面走向，将高架标高替换为数据包中的地面高程，并重新计算三维里程；复用钢轨、承轨台、轨道板和附属设施，不生成箱梁和桥墩。轨道参考线位于地面上方 0.56 m，容纳 0.48 m 的轨道结构、0.06 m 地表走廊及 0.02 m 间隙。贴地精度取决于外部数据包的地面高程采样。

菜单中选择“地面线路”，或直接启动：

```powershell
.\run-preview.ps1 -LocalScene on_ground -SkipDispatch
.\run-preview.ps1 -LocalScene on_ground -SmokeTest
```

调度配置与 outdoors 使用同一线路参数，Esc 返回 on_ground 的调度台。

### 局部水平观察段

`on_ground` 将原里程 8,630–8,730 米附近改为水平直线。考虑四节车厢总长约 109 米及方向采样，直线范围扩展至原里程 8,500–8,770 米，两端各用 100 米过渡接回原线路。直线标高取该范围的最高轨道点，钢轨与地表走廊使用同一修正路线；其他区段保留逐点贴地方式。修改后重新计算三维里程。

默认进入场景会定位到原 8,632 米对应的地理位置并暂停（异常高程修复后约为 8,015 米），按 Space 继续运行。显式指定 hold、capture 或 motion-test 时沿用这些模式的定位。冒烟测试逐米检查目标 100 米范围内四节车厢的高度差和朝向夹角。

### 异常高程修复

`on_ground/elevation_repair.gd` 只处理相对邻域中值偏差超过 20 米、连续不超过 4 点且前后有正常锚点的异常。按水平距离插值补齐缺失高程，其他采样保持原值。当前大糸线数据修复第 1502、1503 个采样点，消除约 315 米的骤降；不改写外部资源包。

修复后轨道、地表走廊、列车和相机共用修正高程，并重新计算真实三维里程。原水平观察段通过旧、新里程映射保持原地理位置；原 8,630–8,730 米区间现约为 8,013–8,113 米。可运行 `--headless --path . --script res://tools/check_elevation_repair.gd` 验证插值和正常采样保持不变。
