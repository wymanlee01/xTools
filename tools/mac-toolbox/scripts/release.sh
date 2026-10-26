#!/bin/zsh
# 生成发布用的安装包 dist/xTools-<版本>.zip，上传到 GitHub Releases 后，旧版本的“检查更新”就能装上
# 步骤：1. 改 VERSION 里的版本号  2. 运行本脚本  3. 按最后打印的提示建 tag、上传 zip
# 必须用 “xTools Dev” 证书签名：自动更新会校验新版本和当前版本是同一张证书
set -euo pipefail

cd "$(dirname "$0")/.."
if ! security find-identity -p codesigning | grep -q '"xTools Dev"'; then
    echo "钥匙串里没有 “xTools Dev” 证书，发布包必须用它签名" >&2
    exit 1
fi

VERSION=$(tr -d '[:space:]' < VERSION)
SIGN_IDENTITY="xTools Dev" ./scripts/bundle.sh
codesign --verify --strict dist/xTools.app

ZIP="dist/xTools-$VERSION.zip"
rm -f "$ZIP"
# ditto 打包能保留签名和扩展属性
ditto -c -k --keepParent dist/xTools.app "$ZIP"

echo
echo "已生成 $ZIP"
echo "发布：在 GitHub 仓库的 Releases 里新建 tag v$VERSION 的正式版（不要勾预发布），把 $ZIP 作为附件上传，说明里写更新内容"
