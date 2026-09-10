# 本地数据来源与加工说明

本包不使用 Google Photorealistic 3D Tiles，也不依赖 Cesium ion。
范围：现有东京—品川 OpenStreetMap 轨道线路，两侧各 500 m。
边缘保留完整建筑和地面分块，所以包的外缘会略超出 500 m。

- 建筑：国土交通省 Project PLATEAU，千代田区、中央区、港区、品川区的最新 LOD2 配信数据（源数据部分建筑为 LOD1）。
  官方入口：https://docs.plateauview.mlit.go.jp/datasets/3d-tiles/
  使用规则：https://www.mlit.go.jp/plateau/site-policy/
  按 CC BY 4.0 兼容规则注明来源。本项目进行了范围筛选、Draco 解码、局部坐标转换和贴图再编码，不是官方原始成果。
- 地面影像：国土地理院 seamlessphoto，Z18。各区域摄影年份与实际分辨率可能不同。
  数据说明：https://maps.gsi.go.jp/development/ichiran.html
  使用规则：https://www.gsi.go.jp/kikakuchousei/kikakuchousei40182.html
- 高程：国土地理院 DEM5A/B/C（Z15）及 DEM10B（Z14）缺值补充，PNG 编码 0.01 m 不代表测量精度 0.01 m。
  规格：https://maps.gsi.go.jp/development/demtile.html
  地面的小范围缺测插值数量和最大距离记录于 manifest.json，轨道采样不使用该缺测插值。
- 高程基准：国土地理院 geoid 计算服务，沿线三处采样后插值。用于视觉对齐，不是测绘工程转换成果。
- 轨道平面线路：© OpenStreetMap contributors，ODbL，见 assets/route。
  高度采用平滑 DEM + 6 m 的视觉估计，不能作为实际高架、轨道坡度或建筑碰撞依据。
- 列车：复用用户提供的模型，未改变其原有权属。

source 目录仅供构建、审计及续传。运行场景只读取 manifest.json 和 models 中的自包含 GLB。
运行画面与 Google 实景摄影测量不同：没有自动补造树木、车辆、站台或精确轨道设施。
