#!/bin/zsh
# 运行单元测试
# 显式指定测试宏插件路径：只装命令行工具时，swift test 偶尔会报
# “plugin for module 'TestingMacros' not found”
set -euo pipefail

cd "$(dirname "$0")/.."
PLUGIN_DIR="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$PLUGIN_DIR" ]]; then
    swift test -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR" "$@"
else
    swift test "$@"
fi
