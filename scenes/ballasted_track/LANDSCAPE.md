# 参考照片周边环境

实时入口 `scene.tscn` 现在启用沿实测曲线分布的乔木、灌木、野草及低缓草坡，搭配夏季日照。原来的实时 `_verges()` 只创建空节点，未使用静态场景的植被。

选择场景根节点，在 Inspector 的 **Trackside landscape** 设置：

- `landscape_enabled`：植被与草坡开关。
- `summer_daylight`：夏日日照；关闭后使用原来的阴天光照。
- `landscape_density`：默认 1；低性能设备可降到 0.5。
- `landscape_view_distance_m`：默认 420 m；低性能设备可降到 220 m。
- `landscape_tree_mesh` / `landscape_shrub_mesh`：可选外部 Mesh 资源，须包含材质、以米为单位、Y 向上、根部为原点；留空使用程序化植物。不是 PackedScene 插槽。导入 GLB 后，可从 MeshInstance3D 的 Mesh 保存资源再赋值。

环境每 64 m 分块，按相机的世界位置加载，每帧最多创建两块；超出范围后释放。种子固定，重访位置不变。树木避开轨道、检修通道及 LY 建筑区域。高速跳转后环境会用数帧补齐；使用距离剔除而非透明渐隐，因此边界仍可能出现跳变。当前为程序化近似，不是照片级复原，也未安装第三方插件。

## 插件方向

- [Terrain3D](https://github.com/TokisanGames/Terrain3D)：编辑大范围地形、坡面和地表材质。若接入，应替换本脚本的草坡生成，并同步植被高度采样，避免两套地表叠加。
- [ProtonScatter](https://github.com/HungryProton/scatter)：按规则布置植被或其他场景资源。若使用其散布结果，应关闭 `landscape_enabled`，避免重复生成。

插件提供地形与布置工具，不会自动提供参考照片中的树木外观。进一步逼近照片需要带真实叶片纹理、法线及 LOD 的乔灌木资源，以及更细致的地表材质。现有 Mesh 插槽可先替换植物；插件版本需按各项目文档与当前 Godot 4.7 核对。

## 验证与截图

```powershell
& E:/Godot_v4.7/Godot_v4.7-stable_win64_console.exe --headless --path E:/GodotSimulator --rendering-method gl_compatibility res://scenes/ballasted_track/scene.tscn -- --demo-smoke-test
& E:/Godot_v4.7/Godot_v4.7-stable_win64_console.exe --path E:/GodotSimulator --rendering-method gl_compatibility res://scenes/ballasted_track/scene.tscn -- --reference-capture --landscape-capture
```

第二条输出 `landscape_preview.png`，使用单独的高位相机并隐藏界面；普通运行保持原有相机和界面。冒烟测试覆盖原有线路/列车检查，以及 2 km 跳转后环境块加载、返回和数量上限。兼容渲染器已进行实际截图检查；未进行长期帧率测试。
