# Travel 路堑铁路

参考 OIP.webp 构建的独立静态场景：1 km 双线无砟轨道、排水沟、电缆槽、三层拱形骨架护坡、边坡踏步和坡顶植被。默认画面包含左线静置列车，无接触网，与参考照片的线路外观一致。

启动：

```powershell
.\run-preview.ps1 -LocalScene travel -SkipDispatch
.\run-preview.ps1 -LocalScene travel -SmokeTest
```

在 Godot 中也可打开 scene.tscn 后按 F6。几何在运行时生成。

- 1：参考图俯视机位
- 2：列车近景
- F1：显示/隐藏操作说明
- Esc：返回场景菜单

列车直接加载项目内 scenes/travel/train/train_car.tscn，模型位于同目录 models 文件夹。保留四节编组、27 m 车长、26.5 m 车心间距、尾车反向和三处风挡，以及转向架与轮对。首尾车体使用 train1.glb，中间两节使用 models/train2.glb；若未提供 train2.glb，则回退到 train1.glb。轮底按模型包围盒对齐轨顶。

travel 不再依赖 E:/game_project 或 -ExternalProject。train_car.tscn 使用本地模型路径，未挂载原始 scripts/train_car.gd：该控制器依赖原项目的 TrackManager，而 travel 由自身进度控制列车位置。原始脚本作为参考保留。首次运行前请在 Godot 编辑器中完成本地 GLB 导入；资源缺失时显示错误，冒烟测试失败。

承轨台和扣件在 outdoors_track.gd 中按照片轮廓生成：台座采用低矮坡面、薄底沿和倒角，底面 0.64 × 0.38 m，混凝土高 0.126 m，顶部承载面 0.414 × 0.29 m，纵向间距 0.65 m。尺寸为外观近似，并非照片测量值。每套扣件含 14 mm 橡胶垫板、两侧挡肩、深灰绝缘块、垫圈、六角螺母、螺栓端部和连续圆弧弹条。轨底位于板面以上 0.14 m；钢轨高 0.16 m，轨顶为 0.46 m，列车轮底同步对齐。轨头内侧间距 1.435 m，中心距 1.505 m。台座与扣件使用共享网格、分块 MultiMesh 和距离裁剪。

直接运行时附加用户参数 --travel-capture 会生成 preview.png 和 track_detail.png 并退出。
