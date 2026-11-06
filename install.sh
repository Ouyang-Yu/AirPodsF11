#!/bin/zsh # 使用 macOS 自带的 zsh 执行安装。
set -euo pipefail # 任一命令失败或变量未定义时立即停止。

# MARK: - 安装路径与服务标识

ROOT_DIR="${0:A:h}" # 获取安装脚本所在项目目录。
SERVICE_LABEL="local.airpodsf11" # 与 LaunchAgent 的 Label 保持一致。
TARGET_APP="$HOME/Applications/AirPodsF11.app" # 使用用户应用目录避免要求管理员权限。
PLIST_TARGET="$HOME/Library/LaunchAgents/$SERVICE_LABEL.plist" # 指定当前用户的登录服务配置。
PLIST_TEMPLATE="$ROOT_DIR/$SERVICE_LABEL.plist" # 指定仓库中的服务配置模板。
USER_DOMAIN="gui/$(id -u)" # 获取当前图形登录会话的 launchd 域。

# MARK: - 停止旧实例并构建

if launchctl print "$USER_DOMAIN/$SERVICE_LABEL" >/dev/null 2>&1; then # 检查旧服务是否已加载。
  launchctl bootout "$USER_DOMAIN/$SERVICE_LABEL" # 卸载旧服务，防止更新期间自动重启。
fi # 结束旧服务检查。
if pgrep -x AirPodsF11 >/dev/null; then # 检查手动启动的旧进程。
  pkill -x AirPodsF11 # 停止旧进程，避免重复注册 F11。
fi # 结束旧进程检查。
"$ROOT_DIR/build.sh" # 编译、执行自检并生成最新应用包。

# MARK: - 备份与安装

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" # 创建所需用户目录。
if [[ -d "$TARGET_APP" ]]; then # 重新安装时保护旧版本。
  BACKUP_APP="$HOME/Applications/AirPodsF11-backup-$(date +%Y%m%d-%H%M%S).app" # 生成带时间戳的备份路径。
  ditto "$TARGET_APP" "$BACKUP_APP" # 在覆盖前完整备份旧应用。
  print "旧应用已备份到：$BACKUP_APP" # 告知备份位置。
fi # 结束旧应用备份。
if [[ -f "$PLIST_TARGET" ]]; then # 重新安装时保护旧服务配置。
  cp "$PLIST_TARGET" "$PLIST_TARGET.backup-$(date +%Y%m%d-%H%M%S)" # 备份旧服务配置。
fi # 结束服务配置备份。
ditto "$ROOT_DIR/dist/AirPodsF11.app" "$TARGET_APP" # 将新应用安装到用户应用目录。

# MARK: - 加载登录服务

PLIST_CONTENT="$(<"$PLIST_TEMPLATE")" # 读取 LaunchAgent 模板。
PLIST_CONTENT="${PLIST_CONTENT//__HOME__/$HOME}" # 将主目录占位符替换为当前用户主目录。
print -r -- "$PLIST_CONTENT" > "$PLIST_TARGET" # 写入当前用户的 LaunchAgent 配置。
chmod 644 "$PLIST_TARGET" # 设置服务配置为当前用户可写、系统可读。
plutil -lint "$PLIST_TARGET" # 验证替换后的 plist 语法。
launchctl bootstrap "$USER_DOMAIN" "$PLIST_TARGET" # 加载服务，RunAtLoad 会立即启动应用。
launchctl print "$USER_DOMAIN/$SERVICE_LABEL" >/dev/null # 确认服务已被 launchd 接收。
print "安装完成，AirPodsF11 已启动并将在每次登录后自动运行。" # 输出安装成功信息。
print "日志位置：$HOME/Library/Logs/AirPodsF11.err.log" # 输出故障排查日志位置。
