#!/bin/zsh # 使用 macOS 自带的 zsh 执行构建。
set -euo pipefail # 任一命令失败或变量未定义时立即停止。

# MARK: - 路径与构建产物

ROOT_DIR="${0:A:h}" # 获取脚本所在项目目录。
APP_DIR="$ROOT_DIR/dist/AirPodsF11.app" # 指定应用程序包输出位置。
BINARY_DIR="$APP_DIR/Contents/MacOS" # 指定可执行文件目录。
ZIP_PATH="$ROOT_DIR/dist/AirPodsF11.zip" # 指定便于分发的压缩包位置。
mkdir -p "$BINARY_DIR" # 创建应用包目录结构。

# MARK: - 原生编译与签名

# 使用优化编译，针对当前 CPU 架构并链接所需系统框架。
swiftc -O -whole-module-optimization \
  -target "$(uname -m)-apple-macosx13.0" \
  -framework Foundation -framework CoreAudio -framework Carbon \
  "$ROOT_DIR/Sources/main.swift" \
  "$ROOT_DIR/Sources/HotKeyListener.swift" \
  "$ROOT_DIR/Sources/ListeningModeController.swift" \
  -o "$BINARY_DIR/AirPodsF11" # 输出后台程序可执行文件。
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist" # 写入应用包元数据。
codesign --force --sign - "$APP_DIR" # 使用本机 ad-hoc 签名保证应用包结构完整。

# MARK: - 构建后验证与打包

"$BINARY_DIR/AirPodsF11" --self-test # 运行不依赖真实耳机的逻辑自检。
"$BINARY_DIR/AirPodsF11" --check-hotkey # 验证当前系统允许注册 F11。
rm -f "$ZIP_PATH" # 删除项目构建目录中的旧压缩包，避免打包嵌套。
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH" # 创建保留 macOS 元数据的 ZIP。
print "构建完成：$APP_DIR" # 输出应用包位置。
print "压缩包：$ZIP_PATH" # 输出压缩包位置。
