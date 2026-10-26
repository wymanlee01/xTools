# mac-toolbox

macOS 菜单栏工具箱（应用名 xTools）。第一版：截图、贴图；后续：粘贴板。

- 技术栈：Swift 6 + AppKit，SwiftPM 构建，最低 macOS 14
- 设计文档：[docs/mac-toolbox-design.md](../../docs/mac-toolbox-design.md)

## 构建与运行

```bash
./scripts/test.sh          # 单元测试
./scripts/bundle.sh        # 生成 dist/xTools.app
open dist/xTools.app
```

只装命令行工具（没有 Xcode）也能构建。
测试请用 `scripts/test.sh`：它显式指定了测试宏插件路径。直接跑 `swift test` 偶尔会报
`plugin for module 'TestingMacros' not found`。

**签名**：系统按代码签名识别应用，屏幕录制权限绑定在签名身份上。
- 临时签名的身份是程序哈希，每次重新编译都会变，系统当成新应用，要重新授权。
- 用固定证书签名时，身份是“包名 + 证书指纹”，重新编译不变，授权一次即可。

`bundle.sh` 会自动使用钥匙串里名为 `xTools Dev` 的代码签名证书；没有时退回临时签名。
也可以用 `SIGN_IDENTITY="证书名称"` 指定其他证书。创建 `xTools Dev` 自签名证书：

```bash
cat > cert.cnf <<'EOF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = xTools Dev
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cert.cnf
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -name "xTools Dev" -out xtools.p12 -passout pass:临时密码
security import xtools.p12 -k ~/Library/Keychains/login.keychain-db -P 临时密码 -T /usr/bin/codesign
rm key.pem cert.pem xtools.p12 cert.cnf
```

`security find-identity -p codesigning` 里显示 `CSSMERR_TP_NOT_TRUSTED` 是正常的（自签名证书未被系统信任），不影响签名。

## 当前功能

| 功能 | 操作 |
|---|---|
| 区域截图 | F1 或菜单栏「区域截图」（没开“将 F1、F2 等键用作标准功能键”时按 fn+F1） |
| 框选 | 拖拽；单击选中光标下的窗口（没有窗口则选整屏）；拖动选区内部可移动 |
| 调整选区 | 拖动 8 个手柄改大小；方向键移动 1 点，⇧+方向键移动 10 点 |
| 放大镜 / 取色 | 框选前和拖拽时跟随光标显示；框选前按 C 复制 HEX，⇧C 复制 RGB（颜色按 sRGB 换算） |
| 标注工具栏 | 按 iShot 1:1 复刻尺寸和布局；选区定下后出现在选区下方；选了工具后选区锁定 |
| 标注工具 | 1 矩形、2 椭圆、3 直线、4 箭头、5 画笔、6 马赛克、7 文字、8 步骤标注、9 高亮（聚光灯）；⇧ 画正方形/圆、锁 45° |
| 样式栏 | 大小、不透明度滑块；5 个预设色 + 自定义色（吸管按钮打开取色面板）；专属选项：矩形实心/圆角、椭圆实心、高亮矩形/椭圆、马赛克/毛玻璃、画笔单一颜色/高斯模糊/马赛克、文字背景（无/底色/描边）+ 背景色 + 字体 |
| 编辑标注 | 点中已有元素可拖动移动，样式栏回显它的样式；Delete 删除；滚轮调不透明度（步骤标注是改序号） |
| 撤销 / 重做 | ⌘Z 或工具栏按钮 / ⇧⌘Z（和 iShot 一样，工具栏没有重做按钮） |
| 悬浮提示 | 鼠标停在按钮上，工具栏上方弹出提示框（工具名 + 快捷键），6 秒后自动隐藏；跟随系统深浅色 |
| 单键快捷键 | 有选区后：1~9 切换工具、空格保存、回车复制；可在提示框的下拉框里改成 0~9 / A~Z（保存、复制还可选空格 ㄩ、回车 ↩），与已有按键冲突时自动互换 |
| 未完成 | 贴图、OCR、长截图按钮先占位置灰；曲线箭头选项置灰 |
| 复制 | 回车 / 双击选区 / ⌘C |
| 保存 | ⌘S，默认存到桌面 |
| 取消 | Esc / 右键 |

## 目录

```
Sources/
├── App/                # 入口：注册模块、菜单栏
├── ToolboxCore/        # 底座：模块协议、快捷键、设置、权限、剪贴板、服务注册
└── FeatureScreenshot/  # 截图模块
```

新增功能模块：建 `Sources/FeatureXxx/`，实现 `ToolModule`，在 `Package.swift` 和 `AppDelegate.modules` 各加一行。
功能模块之间不能互相 import，协作通过 `ServiceRegistry` 里的协议。
