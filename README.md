# 东京—品川站间地形预览

本工程使用 Cesium for Godot，仅预览东海道新干线的第一个站间段：

东京站 → 品川站

时间压缩固定为 1×，参考东海道新干线最高运营速度 285 km/h。东京附近地形完成初始加载后自动发车，到达品川后停止。

## 地形数据

项目根目录的 `cesium_token.txt` 需要包含有效 Cesium ion Token。程序加载 Cesium World Terrain（资产 1）和 Bing Maps Aerial Imagery（资产 2）。

## 操作

- `Space`：暂停/继续
- `R`：重新预览东京到品川

低空高度为 200 m；程序每前进 3 km 会等待当前视野地形 Tile 稳定后再继续。
