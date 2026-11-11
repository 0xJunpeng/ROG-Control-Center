#!/bin/bash
# ROG 奥创中心 · 一键构建 + DMG 打包
set -e
cd "$(dirname "$0")"

APP_NAME="RogControlCenter"
APP="build/${APP_NAME}.app"
VERSION="1.2.0"
DMG_NAME="ROG奥创中心-${VERSION}.dmg"

echo "==> 1/5 生成图标"
mkdir -p Resources
if [ ! -f Resources/AppIcon.icns ]; then
  mkdir -p /tmp/rog.iconset
  swift Tools/make_icon.swift /tmp/rog_1024.png
  sips -z 16 16     /tmp/rog_1024.png --out /tmp/rog.iconset/icon_16x16.png      >/dev/null
  sips -z 32 32     /tmp/rog_1024.png --out /tmp/rog.iconset/icon_16x16@2x.png   >/dev/null
  sips -z 32 32     /tmp/rog_1024.png --out /tmp/rog.iconset/icon_32x32.png      >/dev/null
  sips -z 64 64     /tmp/rog_1024.png --out /tmp/rog.iconset/icon_32x32@2x.png   >/dev/null
  sips -z 128 128   /tmp/rog_1024.png --out /tmp/rog.iconset/icon_128x128.png    >/dev/null
  sips -z 256 256   /tmp/rog_1024.png --out /tmp/rog.iconset/icon_128x128@2x.png >/dev/null
  sips -z 256 256   /tmp/rog_1024.png --out /tmp/rog.iconset/icon_256x256.png    >/dev/null
  sips -z 512 512   /tmp/rog_1024.png --out /tmp/rog.iconset/icon_256x256@2x.png >/dev/null
  sips -z 512 512   /tmp/rog_1024.png --out /tmp/rog.iconset/icon_512x512.png    >/dev/null
  sips -z 1024 1024 /tmp/rog_1024.png --out /tmp/rog.iconset/icon_512x512@2x.png >/dev/null
  iconutil -c icns /tmp/rog.iconset -o Resources/AppIcon.icns
  echo "    图标已生成 Resources/AppIcon.icns"
fi

echo "==> 2/5 创建 Bundle 结构"
rm -rf build dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

echo "==> 2.5/5 打包内置驱动（离线安装用）"
mkdir -p Resources/Kexts "$APP/Contents/Resources/Kexts"
if [ -d "../Sensors/build/NvFanProbe.kext" ]; then
  ( cd ../Sensors/build && ditto -c -k --sequesterRsrc --keepParent NvFanProbe.kext \
      "../../RogControlCenter/Resources/Kexts/NvFanProbe.kext.zip" )
  echo "    已打包 NvFanProbe.kext（$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' ../Sensors/build/NvFanProbe.kext/Contents/Info.plist)）"
else
  echo "    ⚠️ 未找到 Sensors/build/NvFanProbe.kext，先跑 Sensors/build_kext.sh"
fi
cp Resources/Kexts/*.zip "$APP/Contents/Resources/Kexts/" 2>/dev/null || true

echo "==> 3/5 编译 Swift 源码"
swiftc -O -swift-version 5 -parse-as-library \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/${APP_NAME}"

echo "==> 4/5 代码签名 (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> 5/5 制作 DMG"
mkdir -p dist
cp -R "$APP" dist/
ln -s /Applications dist/Applications
hdiutil create -volname "ROG奥创中心" -srcfolder dist -ov -format UDZO "../${DMG_NAME}" >/dev/null

echo ""
echo "✅ 构建完成:"
echo "   App : $(pwd)/$APP"
echo "   DMG : $(pwd)/../${DMG_NAME}"
