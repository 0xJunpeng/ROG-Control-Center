#!/bin/bash
# ROG 奥创中心 · SMC 传感器修复验证脚本（v2）
# 用法：bash "/Users/yangjp/Documents/Code/ROG奥创/verify_smc.sh"
APP="/Users/yangjp/Documents/Code/ROG奥创/RogControlCenter/build/RogControlCenter.app/Contents/MacOS/RogControlCenter"

echo "=== 1. App 内置 SMC 采样（等 3 秒；重点看 temp= 和 fans=）==="
"$APP" --smc-test 2>&1 | grep RESULT

echo ""
echo "=== 2. kext 加载状态 ==="
kextstat 2>/dev/null | grep -iE "SMCProcessor|SMCSuperIO|VirtualSMC" | awk '{print $6, $7, "refs="$5}'

echo ""
echo "=== 3. 内核日志：SMCProcessor / 传感器插件 / IOKit 匹配 ==="
/usr/bin/log show --last 2h --style compact 2>/dev/null \
  | grep -E "\(scpu\)|\(scio\)|\(vsmc\)|SMCProcessor" \
  | grep -v "RBSCPU" | head -25

echo ""
echo "=== 4. IOKit 匹配日志（io=0x800216 开启，查找 SMCProcessor 相关）==="
/usr/bin/log show --last 2h --style compact 2>/dev/null \
  | grep -iE "IOService.*SMC|SMCProcessor.*match|no class named|class .*SMCProcessor" \
  | head -10

echo ""
echo "=== 完成。若 temp=0.0，请把上面全部输出发给助手 ==="
