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

列车通过 outdoors 的 external_resources.gd 加载 E:/game_project/train/scenes/train_car.tscn 和 train2.glb；沿用四节编组、27 m 车长、27.3 m 车心间距、尾车反向和三处风挡。包含原场景的转向架与轮对。轮底按模型包围盒对齐轨顶，列车静置不自动行驶。

外部资源不复制，移动外部项目后使用 -ExternalProject 指定新目录。缺失时显示错误，冒烟测试失败。场景其余内容为本地程序化几何。

承轨台与扣件采用 outdoors 的结构和材质，在 outdoors_track.gd 中本地复用：承轨台 0.45 × 0.22 × 0.32 m，纵向间距 0.65 m；每套扣件含轨下垫板、挡肩、绝缘块、垫圈、六角螺母和弯曲弹条。钢轨同步采用 0.16 m 高截面，轨顶为 0.54 m，列车轮底同步调整。轨头内侧间距 1.435 m，中心距 1.505 m。

直接运行时附加用户参数 --travel-capture 会生成 preview.png 和 track_detail.png 并退出。
