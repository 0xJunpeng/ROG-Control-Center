#!/bin/bash
# NvFanProbe.kext 构建脚本（无 Xcode 工程，直接用 CLT 工具链）
set -e
cd "$(dirname "$0")"

SDK=$(xcrun --show-sdk-path)
OUT="build/NvFanProbe.kext"

rm -rf build
mkdir -p "$OUT/Contents/MacOS"

echo "==> 编译 NvFanProbe.cpp"
clang++ -fapple-kext -fno-exceptions -fno-rtti -fno-implicit-templates -mkernel -nostdinc++ -std=c++11 \
  -DAPPLE -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DNeXT \
  -isysroot "$SDK" \
  -I"$SDK/System/Library/Frameworks/Kernel.framework/Headers" \
  -arch x86_64 -mmacosx-version-min=10.15 -O2 \
  -Wall \
  -c NvFanProbe/NvFanProbe.cpp -o build/NvFanProbe.o

echo "==> 链接为 kext bundle"
# 入口函数由源码自己提供（NvFanProbeKernStart/Stop），
# 不能链 libkmod.a —— 其 _start 依赖内核私有符号 __realmain，链接期会失败
ld -r -arch x86_64 -o "$OUT/Contents/MacOS/NvFanProbe" build/NvFanProbe.o -kext
nm -arch x86_64 "$OUT/Contents/MacOS/NvFanProbe" | grep -E "KernStart|_kmod_info"

echo "==> 写入 Info.plist"
cp NvFanProbe/Info.plist "$OUT/Contents/Info.plist"

chmod -R go-w "$OUT"
echo "==> 结果"
file "$OUT/Contents/MacOS/NvFanProbe"
echo "✅ $OUT"
