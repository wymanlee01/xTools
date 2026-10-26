#!/bin/zsh
# 编译并打包成 dist/xTools.app
# 签名优先级：环境变量 SIGN_IDENTITY → 钥匙串里的 “xTools Dev” 证书 → 临时签名
# 用固定证书签名时，屏幕录制授权不会因重新编译失效；临时签名每次重新编译后都要重新授权
set -euo pipefail

if [[ -z "${SIGN_IDENTITY:-}" ]] && security find-identity -p codesigning | grep -q '"xTools Dev"'; then
    SIGN_IDENTITY="xTools Dev"
fi

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
    <!-- 录屏时录制麦克风需要说明用途 -->
    <key>NSMicrophoneUsageDescription</key><string>录屏时录制麦克风声音</string>
    <!-- 只在菜单栏显示，不出现在 Dock -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "已生成 $APP（签名：${SIGN_IDENTITY:-临时签名}）"
