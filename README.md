# AirPodsF11

一个轻量的 macOS 后台工具：按一下 **F11**，在 AirPods 的 **降噪** 与 **通透** 模式之间切换。

## 特点

- 原生 Swift，无 Electron、无第三方依赖。
- 无窗口、无 Dock 图标、无菜单栏图标。
- 直接通过 Core Audio 控制设备，不弹出控制中心。
- 不需要辅助功能或输入监听权限。
- 不访问网络，不收集或上传任何数据。
- 支持登录自启动与异常退出后自动恢复。
- 写入后立即返回，没有状态轮询等待。

## 系统要求

- macOS 13 或更高版本。
- 支持聆听模式的 AirPods 或兼容 Beats 耳机。
- 从源码构建时需要 Xcode Command Line Tools。

已在 macOS 27.2 与 AirPods Pro 上完成实际切换验证。不同 macOS 版本和耳机型号可能存在差异。

## 快速使用

1. 从 Releases 下载并解压 `AirPodsF11.zip`。
2. 打开 `AirPodsF11.app`。
3. 连接 AirPods，按 **F11** 切换模式。

如果键盘将 F11 默认用作音量键，请按 **Fn + F11**，或在 macOS 键盘设置中启用“将 F1、F2 等键用作标准功能键”。

当前处于“自适应”或“关闭”模式时，第一次触发会进入“降噪”，之后在“降噪”和“通透”之间往返。

## 从源码安装并设置自启动

```sh
git clone https://github.com/Ouyang-Yu/AirPodsF11.git
cd AirPodsF11
./install.sh
```

安装脚本会：

1. 停止旧实例。
2. 编译源码并运行自检。
3. 将应用安装到 `~/Applications/AirPodsF11.app`。
4. 创建 `~/Library/LaunchAgents/local.airpodsf11.plist`。
5. 通过 launchd 启动应用，并启用登录自启动和异常退出恢复。

重新安装时，旧应用和旧服务配置会先备份到对应用户目录。

## 只构建，不安装

```sh
./build.sh
open dist/AirPodsF11.app
```

构建产物：

- `dist/AirPodsF11.app`：可直接打开的应用。
- `dist/AirPodsF11.zip`：便于分发的应用压缩包。

## 诊断命令

以下命令通过应用内的可执行文件运行：

```sh
# 查看兼容设备与当前模式
~/Applications/AirPodsF11.app/Contents/MacOS/AirPodsF11 --status

# 不经过 F11，直接切换一次
~/Applications/AirPodsF11.app/Contents/MacOS/AirPodsF11 --toggle

# 运行模式计算自检
~/Applications/AirPodsF11.app/Contents/MacOS/AirPodsF11 --self-test

# 检查 F11 能否注册
~/Applications/AirPodsF11.app/Contents/MacOS/AirPodsF11 --check-hotkey
```

运行日志位于：

```text
~/Library/Logs/AirPodsF11.err.log
~/Library/Logs/AirPodsF11.out.log
```

## 停止或恢复自启动服务

临时停止当前服务：

```sh
launchctl bootout "gui/$(id -u)/local.airpodsf11"
```

重新加载并启动：

```sh
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.airpodsf11.plist"
```

如需彻底移除，先停止服务，再通过 Finder 将以下项目移到废纸篓：

- `~/Applications/AirPodsF11.app`
- `~/Library/LaunchAgents/local.airpodsf11.plist`

## 实现说明

- 使用 Carbon `RegisterEventHotKey` 注册无修饰键的全局 F11。
- 使用 Core Audio 的 `lstm` 属性读取和写入聆听模式。
- 使用 `lsms` 位掩码确认设备是否支持降噪与通透。
- 使用串行队列避免并发切换，并过滤 350 毫秒内的重复热键事件。
- 使用 launchd 的 `RunAtLoad` 和 `KeepAlive` 管理生命周期。

`lstm` 和 `lsms` 属于 macOS 未公开文档化的设备属性，未来系统升级可能要求适配。本项目不直接实现蓝牙协议，也不绕过系统权限；实际设备通信仍由 macOS 音频与蓝牙栈完成。

## 贡献

欢迎提交 Issue 或 Pull Request，尤其是在不同 macOS 版本、AirPods 和 Beats 型号上的兼容性反馈。

## 致谢

- [pods-control](https://github.com/raulgg/airpods-control)：Core Audio 聆听模式属性与设备行为调研参考。
- [AirPodsToggle](https://github.com/chrbang/AirPodsToggle)：macOS 26+ Carbon 热键与后台事件处理调研参考。

## 许可证

[MIT License](LICENSE)
