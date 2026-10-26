#!/bin/zsh
# 编译并打包成 dist/xTools.app
# 签名：设置 SIGN_IDENTITY 用固定证书签名（推荐，屏幕录制授权不会因重新编译失效）
#      不设置则用临时签名，每次重新编译后都要重新授权
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG=${CONFIG:-release}
APP=dist/xTools.app

swift build -c "$CONFIG"
BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/App" "$APP/Contents/MacOS/xTools"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.wymanlee01.xtools</string>
    <key>CFBundleName</key><string>xTools</string>
    <key>CFBundleExecutable</key><string>xTools</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- 只在菜单栏显示，不出现在 Dock -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "已生成 $APP（签名：${SIGN_IDENTITY:-临时签名}）"
