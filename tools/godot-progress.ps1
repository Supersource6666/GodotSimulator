# Translate Godot editor progress messages without changing editor preferences.
function Convert-GodotProgressToEnglish {
    process {
        $line = [string]$_
        $messages = @{
            '项目初始化' = 'Initializing project'
            '正在扫描文件结构' = 'Scanning file structure'
            '正在加载全局类名' = 'Loading global class names'
            '正在校验 GDExtension' = 'Verifying GDExtensions'
            '正在创建自动加载脚本' = 'Creating autoload scripts'
            '正在初始化插件' = 'Initializing plugins'
            '正在启动文件扫描' = 'Starting file scan'
            '正在注册全局类' = 'Registering global classes'
            '正在扫描动作' = 'Scanning actions'
            '正在导入或重新导入资产' = 'Importing or reimporting assets'
            '正在准备重新加载文件' = 'Preparing to reload files'
            '正在执行重新加载前的操作' = 'Running pre-reload operations'
            '正在结束资产导入' = 'Finishing asset import'
            '正在更新脚本文档' = 'Updating script documentation'
            '正在执行重新加载后的操作' = 'Running post-reload operations'
            '正在加载编辑器布局' = 'Loading editor layout'
            '正在加载停靠面板' = 'Loading docks'
            '正在重新打开场景' = 'Reopening scenes'
            '正在加载中央编辑器布局' = 'Loading central editor layout'
            '正在加载插件窗口布局' = 'Loading plugin window layout'
            '编辑器布局就绪' = 'Editor layout ready'
            '正在加载编辑器' = 'Loading editor'
        }
        foreach ($source in ($messages.Keys | Sort-Object Length -Descending)) {
            $line = $line.Replace($source, $messages[$source])
        }
        $line.Replace('……', '...').Replace('。', '.')
    }
}