# 本地预览资源准备

本文说明如何准备东京—品川离线预览资源，并运行本地场景。以下命令均在项目根目录执行：

```powershell
cd C:\GodotEngine\GodotProject\rail_project
```

## 1. 运行环境

- Windows PowerShell。
- Godot 4.x。本机使用：

  ```text
  C:\GodotEngine\Godot_v4.4.1-stable_win64.exe\Godot_v4.4.1-stable_win64.exe
  ```

- Conda 环境 `rail_project`，Python 路径为：

  ```text
  C:\Users\32162\AppData\Local\miniconda3\envs\rail_project\python.exe
  ```

- 构建离线包时需要网络连接。
- 建议至少预留数 GB 磁盘空间。清单中的 302 个运行时模型合计约 0.69 GiB，此外还会产生下载源文件和 Godot 导入缓存。
- 运行时使用 Godot `forward_plus` 渲染，需要兼容的显卡和驱动；具体性能取决于显卡、内存和磁盘速度。

## 2. 安装 Python 依赖

激活 Conda 环境并确认 Python 版本：

```powershell
conda activate rail_project
python --version
```

应显示 Python 3.11。然后安装构建依赖：

```powershell
python -m pip install numpy Pillow DracoPy==1.7.0
```

验证依赖：

```powershell
python -c "import numpy, PIL, DracoPy; print('Python dependencies OK')"
```

也可以不激活环境，直接使用固定路径：

```powershell
& 'C:\Users\32162\AppData\Local\miniconda3\envs\rail_project\python.exe' -m pip install numpy Pillow DracoPy==1.7.0
```

## 3. 构建离线资源

`run-preview.ps1 -Local` 不会自动生成资源。首次运行、下载中断后续传或需要重新导入时，先执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-offline.ps1 `
  -PythonPath 'C:\Users\32162\AppData\Local\miniconda3\envs\rail_project\python.exe' `
  -GodotPath 'C:\GodotEngine\Godot_v4.4.1-stable_win64.exe\Godot_v4.4.1-stable_win64.exe'
```

构建过程会：

1. 读取或生成 `offline_data/plan.json`。
2. 下载并加工离线数据。
3. 生成 `offline_data/models/` 下的自包含模型。
4. 更新 `offline_data/manifest.json`。
5. 调用 Godot 导入资源并生成 `.godot/` 缓存。

下载中断后可以重新执行同一命令，脚本会复用已经下载的文件。需要重新生成构建计划时增加 `-Replan`：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-offline.ps1 `
  -PythonPath 'C:\Users\32162\AppData\Local\miniconda3\envs\rail_project\python.exe' `
  -GodotPath 'C:\GodotEngine\Godot_v4.4.1-stable_win64.exe\Godot_v4.4.1-stable_win64.exe' `
  -Replan
```

## 4. 验证离线包

构建完成后执行完整性检查：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-offline.ps1 `
  -PythonPath 'C:\Users\32162\AppData\Local\miniconda3\envs\rail_project\python.exe' `
  -GodotPath 'C:\GodotEngine\Godot_v4.4.1-stable_win64.exe\Godot_v4.4.1-stable_win64.exe' `
  -VerifyOnly
```

运行本地预览前，应至少存在：

- `offline_data/manifest.json`
- `offline_data/models/`
- `.godot/` 导入缓存

## 5. 启动本地预览

```powershell
powershell -ExecutionPolicy Bypass -File .\run-preview.ps1 -Local
```

需要循环运行时：

```powershell
powershell -ExecutionPolicy Bypass -File .\run-preview.ps1 -Local -Loop
```

本地预览运行阶段不需要网络、Cesium Token 或本地 Web 服务。

> 注意：脚本文件位于项目根目录，正确路径是 `.\run-preview.ps1`，不是 `.\run-preview\.ps1`。