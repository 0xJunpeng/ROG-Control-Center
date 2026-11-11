#!/bin/bash
# 重启后一键验证：传感器 kext 是否加载 / 温度是否读到 / 网速是否正常
echo "=============== 传感器 kext 状态 ==============="
if /usr/bin/kmutil showloaded 2>/dev/null | grep -q NvFanProbe; then
  echo "kext 已加载："
  /usr/bin/kmutil showloaded 2>/dev/null | grep NvFanProbe
else
  echo "❌ kext 未加载"
fi

echo
echo "=============== IORegistry 节点 ==============="
if /usr/sbin/ioreg -w0 -l -r -c NvFanProbe 2>/dev/null | grep -q NvFanProbe; then
  /usr/sbin/ioreg -w0 -l -r -c NvFanProbe | grep -E "CPUTempC|TjMax|Heartbeat|Source"
else
  echo "❌ 没有 NvFanProbe 节点（kext 启动失败）"
fi

echo
echo "=============== App 采样（3 秒）==============="
APP="/Applications/RogControlCenter.app/Contents/MacOS/RogControlCenter"
if [ -x "$APP" ]; then
  "$APP" --smc-test 2>&1 | grep RESULT
else
  echo "❌ 未安装 /Applications/RogControlCenter.app"
fi
