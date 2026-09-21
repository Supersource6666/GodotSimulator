# 有砟轨道 / ballasted_track

从项目场景菜单选择“有砟轨道”，或直接运行 scene.tscn。

600 m 双线地面铁路；1.435 m 内侧轨距，0.6 m 轨枕间距。
道床具有平顶、肩部和约 1:1.67 边坡。约 49.6 万块固定种子的碎石实例，8 种带平整断面的不规则网格，近处以约 35–80 mm 可见粒径为主。轨枕占位避让、灰绿矿物色差和细粒材质，钢轨区分锈蚀腹板与磨亮轨顶。
12 m 道砟分块和距离剔除；84 m 后采用较疏的较大颗粒。这是静态视觉场景，没有列车运行或物理碰撞。

- 右键拖动：转动视角；WASD：移动；Q/E：升降；Shift：加速
- R：参考视角；2：道砟近景；3：全景；F1：说明；Esc：返回
- --demo-smoke-test：检查石块/轨枕数量和实例网格
- --reference-capture：导出 preview.png 后退出
- --reference-capture --detail-capture：导出 detail.png 后退出

纯程序化几何和材质，无外部下载资源。复用现有无砟展示场景的环境、界面和扣件生成辅助，不修改原场景。为兼容当前 AMD R5 M330，关闭会造成黑块的 SSAO，保留方向光阴影。

## 轨枕与扣件更新
参照所提供的新 II 型枕外形和螺栓弹条扣件剖面，使用封闭倒角轨枕、独立承轨台、中央收腰；四千组扣件包含轨下弹性垫、轨距挡块、双趾弹条、垫圈、六角螺母及外露螺纹。按 4 查看扣件特写，R 返回参考视角。可用 --reference-capture --hardware-capture 导出 fastening_detail.png。模型按图片比例进行视觉重建，未依据完整制造图确定所有零件尺寸。

扣件覆盖全部 2,000 根轨枕的 4,000 个承轨点，取消扣件距离隐藏；轨枕与扣件配色参照最初铁路实景图，采用暖灰米色混凝土、深红褐色弹条和暗褐色紧固件。

## 环境与植被
灰白云层天空、低饱和草地与土路、柔和偏中性的阴天照明。两侧原球形树冠替换为带树干分枝和独立折叠叶片的 6 种程序化乔灌木，固定种子布置 1,375 株，右侧密植林缘和灌木下层，左侧开阔低灌木与远树线；两侧铺设 27,500 丛草。植物按 24 m 分块，并使用距离剔除。

## 列车模型
场景左侧轨道静态摆放一节头车和一节中间车，直接引用 train/models 下的 train1.glb、train2.glb、bogie0720.glb 和 wheelset0720.glb。每节车包含两台转向架和四组轮对，轮底对齐轨顶；在编辑器中展开 Train 可调整摆放。

## LY 建筑
参照 LY.jpg 增加白墙蓝边的 LY 用房及跨轨钢结构棚；包含卷帘门、防护窗、红色 LY 标识、屋面护栏、爬梯、排水管和混凝土场坪。尺寸按照片与轨距估算，棚顶高于接触网，建筑周边植被避让。几何按材质合批。
按 5 切换建筑观察视角；使用 --reference-capture --ly-capture 导出 ly_preview.png。建筑生成代码为 ly_building.gd。

## 31DOF 实时数据与平断面轨道

场景入口现使用 `ballasted_track_realtime.gd`：启动时读取 `data/ping_duan_mian.csv`，重建 8 km 曲线轨道系统，并监听 `railway31dof.v1` 或 `railway_ltd.v1` UDP 数据（默认 `127.0.0.1:49000`）。求解器使用 `--godot-stream` 后，列车按绝对里程沿中心线运行，车体、构架、轮对与车轮滚动同步更新。

## LTD 实时驱动

场景启动后，从 `simulation_platform` 根目录运行：

```powershell
.\build\railway_vehicle\Release\railway_ltd.exe `
  --config applications/railway_vehicle/config/25t_yz_loaded_3d_measured_plan_180s.json `
  --duration 180 --dt 0.001 `
  --godot-stream
```

LTD 在线模式每步同步计算和发送，不写入结果文件；场景使用绝对里程驱动整列车沿重建线路运行，并使用实时速度驱动车轮滚动。
