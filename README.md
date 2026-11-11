# ROG 奥创中心（ROG Control Center）

为黑苹果打造的「奥创中心」风格控制台：原生 SwiftUI + AppKit 菜单栏常驻，配套自研内核传感器驱动，专为 **华硕 ROG 枪神6 Plus（ROG Strix SCAR 17 / i9-12900H）+ macOS Tahoe 26** 调校，其他 Intel 黑苹果同样可用。

> 配套 EFI 仓库：[ROG-Strix-SCAR17-Hackintosh-EFI](https://github.com/0xJunpeng/ROG-Strix-SCAR17-Hackintosh-EFI)

## 功能

- **驱动中心**：扫描 EFI/OC/Kexts 与 config.plist，一键安装（GitHub 下载 / 本地导入 / 内置离线驱动）、启用、禁用、卸载，依赖顺序自动排序（Lilu → VirtualSMC → 插件），每次操作前自动备份 config.plist，支持一键回滚
- **硬件探测**：自动识别声卡 codec、有线/无线网卡、显卡型号并推荐对应驱动
- **实时监控**：CPU / 内存 / 磁盘占用、上下行网速（内核级传感器提供温度）
- **菜单栏小部件**：CPU / RAM / SSD 斜切胶囊 + 网速，深浅色自适应，显示项可开关
- **性能与风扇 / 键盘灯效 / 高级 / 设置**：性能模式、采样间隔、开机自启、诊断报告

## 为什么需要 NvFanProbe

macOS 26 起，`AppleSMC` 的用户态私有接口对第三方进程一律返回 `kIOReturnBadArgument`（selector、打开类型、结构体尺寸全试过），VirtualSMC 的 SMCProcessor 在很多机型上也不会实例化 —— 温度在用户态彻底拿不到。

**NvFanProbe.kext** 在内核层直接读 MSR（`0x1A2` TjMax + `0x1B1`/`0x19C` 温度读数），每秒刷新并以 IORegistry 属性 `CPUTempC` 发布，用户态无需 root 即可读取。

- 源码：`Sensors/NvFanProbe/`（无 Xcode 工程，`Sensors/build_kext.sh` 一键构建）
- 编译好的 kext：随 App 内置（驱动中心 → 核心 → NvFanProbe → 安装），也在 EFI 仓库 `EFI/OC/Kexts/NvFanProbe.kext`

## 构建

```bash
# 传感器 kext（需要 Xcode Command Line Tools）
cd Sensors && bash build_kext.sh

# App + DMG
cd RogControlCenter && bash build.sh
# 产物：RogControlCenter/build/RogControlCenter.app 与 ../ROG奥创中心-<版本>.dmg
```

## 目录结构

```
├── RogControlCenter/    # 控制台 App（SwiftUI + AppKit）
│   ├── Sources/         # 全部 Swift 源码
│   ├── Resources/Kexts/ # 内置离线驱动载荷
│   ├── Tools/           # 图标生成
│   └── build.sh         # 一键构建 + DMG
├── Sensors/             # NvFanProbe 内核传感器驱动
│   ├── NvFanProbe/      # C++ 源码 + Info.plist
│   ├── build_kext.sh    # 构建脚本
│   └── build/           # 编译产物 NvFanProbe.kext
├── verify_sensors.sh    # 重启后验证传感器
└── index.html           # 最初的设计原型
```

## 声明

仅供个人学习与黑苹果社区交流使用，与 ASUS / ROG 官方无关。修改 EFI 与安装内核扩展有风险，请自行备份。
