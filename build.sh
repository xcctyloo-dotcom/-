#!/usr/bin/env bash
# 在 macOS 上构建未签名 IPA（TrollStore 可直接安装）
set -euo pipefail
cd "$(dirname "$0")"

OUT="build"
APP_NAME="CarPlayCast"

rm -rf "$OUT"
mkdir -p "$OUT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> 安装 xcodegen"
  brew install xcodegen
fi

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> 编译 (arm64, 不签名)"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -target "${APP_NAME}" \
  -configuration Release \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  SYMROOT="$(pwd)/${OUT}/sym" \
  build

APP="${OUT}/sym/Release-iphoneos/${APP_NAME}.app"
[ -d "$APP" ] || { echo "找不到 $APP"; exit 1; }

echo "==> ldid 写入 CarPlay entitlement"
if ! command -v ldid >/dev/null 2>&1; then
  brew install ldid
fi
ldid -S"${APP_NAME}.entitlements" "${APP}/${APP_NAME}"

echo "==> 打包 Payload"
mkdir -p "${OUT}/Payload"
cp -R "$APP" "${OUT}/Payload/"
rm -rf "${OUT}/Payload/${APP_NAME}.app/_CodeSignature"

(cd "$OUT" && zip -qry "${APP_NAME}.ipa" Payload)

echo "==> 完成: ${OUT}/${APP_NAME}.ipa"
echo "==> 校验: ldid -e ${OUT}/Payload/${APP_NAME}.app/${APP_NAME}"
