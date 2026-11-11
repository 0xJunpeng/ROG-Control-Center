import Foundation

// MARK: - 驱动分类
enum DriverCategory: String, CaseIterable, Identifiable {
    case core     = "核心"
    case audio    = "音频"
    case network  = "网络"
    case graphics = "显卡"
    case storage  = "存储与 USB"
    case laptop   = "笔记本"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .core:     return "cpu"
        case .audio:    return "speaker.wave.2.fill"
        case .network:  return "wifi"
        case .graphics: return "display"
        case .storage:  return "externaldrive.fill"
        case .laptop:   return "laptopcomputer"
        }
    }
}

// MARK: - 驱动条目定义
struct DriverSpec: Identifiable {
    let id: String              // bundle identifier
    let name: String            // 显示名
    let category: DriverCategory
    let summary: String         // 一句话说明
    let repo: String?           // GitHub owner/name（自动下载用，需命名规范）
    let homepage: String?       // 手动下载页
    let required: Bool          // 是否为基础依赖
    let note: String            // 安装/排错提示
    /// 应用内自带的 kext（离线可装，随 App 打包发布）
    var bundled: Bool = false

    var autoDownloadable: Bool { repo != nil }

    /// 判断某个已安装 kext 是否对应本条目
    /// （社区分支常改 bundle 前缀，如 ru.joedm.SMCSuperIO，因此逐级放宽）
    func matches(bundle: String, displayName: String, bundlePath: String) -> Bool {
        if bundle.caseInsensitiveCompare(id) == .orderedSame { return true }
        if bundle.split(separator: ".").last.map(String.init)?.caseInsensitiveCompare(name) == .orderedSame { return true }
        if displayName.caseInsensitiveCompare(name) == .orderedSame { return true }
        if bundlePath.caseInsensitiveCompare(name + ".kext") == .orderedSame { return true }
        return false
    }
}

// MARK: - 内置驱动库
//
// 面向 OpenCore 黑苹果：每一条都对应真实存在的开源 kext。
// repo 非空的（acidanthera 系）服从 `名称-版本-RELEASE.zip` 的资产命名，
// 可一键下载安装；其余给出官方发布页，由用户下载后从本地导入。
enum DriverCatalog {

    static let all: [DriverSpec] = core + audio + network + graphics + storage + laptop

    static func spec(for bundle: String) -> DriverSpec? {
        all.first { $0.id.caseInsensitiveCompare(bundle) == .orderedSame }
    }

    // MARK: 核心依赖
    static let core: [DriverSpec] = [
        DriverSpec(
            id: "com.yangjp.NvFanProbe",
            name: "NvFanProbe",
            category: .core,
            summary: "本机自研传感器驱动：内核层直读 MSR，绕过 macOS 26 关闭的 SMC 用户态通道，提供 CPU 温度。",
            repo: nil,
            homepage: "https://github.com/0xJunpeng/ROG-Strix-SCAR17-Hackintosh-EFI",
            required: false,
            note: "随 App 内置，离线可直接安装。装好后重启，IORegistry 里会出现 CPUTempC 属性，状态栏与「性能与风扇」页同步显示温度。",
            bundled: true
        ),
        DriverSpec(
            id: "as.vit9696.Lilu",
            name: "Lilu",
            category: .core,
            summary: "所有插件型 kext 的加载框架，必须最先加载。",
            repo: "acidanthera/Lilu",
            homepage: "https://github.com/acidanthera/Lilu/releases",
            required: true,
            note: "AppleALC / WhateverGreen / VirtualSMC 全部依赖它，且必须排在它们之前。"
        ),
        DriverSpec(
            id: "as.vit9696.VirtualSMC",
            name: "VirtualSMC",
            category: .core,
            summary: "模拟 SMC 芯片，让 macOS 认为存在系统管理控制器。",
            repo: "acidanthera/VirtualSMC",
            homepage: "https://github.com/acidanthera/VirtualSMC/releases",
            required: true,
            note: "缺失会导致电源管理、温度、风扇、电池全部异常。"
        ),
        DriverSpec(
            id: "as.vit9696.WhateverGreen",
            name: "WhateverGreen",
            category: .graphics,
            summary: "核显/独显修补，负责亮屏、HEVC 硬解、HDMI 音频。",
            repo: "acidanthera/WhateverGreen",
            homepage: "https://github.com/acidanthera/WhateverGreen/releases",
            required: true,
            note: "12 代核显（UHD 770）无原生驱动，配合 AAPL,ig-platform-id 使用。"
        ),
        DriverSpec(
            id: "b00t0x.CpuTopologyRebuild",
            name: "CpuTopologyRebuild",
            category: .core,
            summary: "重建 12 代及以上的 P/E 核拓扑，提升调度与跑分。",
            repo: "b00t0x/CpuTopologyRebuild",
            homepage: "https://github.com/b00t0x/CpuTopologyRebuild/releases",
            required: false,
            note: "需要配合 `-ctrsmt` 启动参数；非大小核 CPU 不需要。"
        ),
        DriverSpec(
            id: "com.dhinakg.AMFIPass",
            name: "AMFIPass",
            category: .core,
            summary: "在保持 AMFI 开启的前提下放行被签名校验拦截的驱动。",
            repo: "dhinakg/AMFIPass",
            homepage: "https://github.com/dhinakg/AMFIPass/releases",
            required: false,
            note: "装 NVIDIA 老卡驱动、部分网卡驱动时必需，配合 `amfi_get_out_of_my_way=1` 使用。"
        ),
        DriverSpec(
            id: "as.vit9696.RestrictEvents",
            name: "RestrictEvents",
            category: .core,
            summary: "屏蔽内存/CPU 型号告警，修正「内存升级」弹窗。",
            repo: "acidanthera/RestrictEvents",
            homepage: "https://github.com/acidanthera/RestrictEvents/releases",
            required: false,
            note: "常配合 `revpatch=sbvmm` 等参数，用于自定义机型信息。"
        ),
        DriverSpec(
            id: "org.lvs1974.driver.CpuTscSync",
            name: "CpuTscSync",
            category: .core,
            summary: "同步多核 TSC，避免唤醒后计时漂移或卡顿。",
            repo: nil,
            homepage: "https://github.com/lvs1974/CpuTscSync/releases",
            required: false,
            note: "HEDT / 多路平台常见；普通桌面平台一般不需要。"
        ),
        DriverSpec(
            id: "org.acidanthera.NVMeFix",
            name: "NVMeFix",
            category: .core,
            summary: "NVMe 固态电源管理与兼容性修补。",
            repo: "acidanthera/NVMeFix",
            homepage: "https://github.com/acidanthera/NVMeFix/releases",
            required: false,
            note: "解决部分 NVMe 盘无法休眠、掉盘、温度异常。"
        ),
        DriverSpec(
            id: "as.vit9696.SMCProcessor",
            name: "SMCProcessor",
            category: .core,
            summary: "通过 SMC 暴露 CPU 温度/频率，iStat 类工具依赖它。",
            repo: "acidanthera/VirtualSMC",
            homepage: "https://github.com/acidanthera/VirtualSMC/releases",
            required: false,
            note: "VirtualSMC 插件，版本必须与 VirtualSMC 完全一致。"
        )
    ]

    // MARK: 音频
    static let audio: [DriverSpec] = [
        DriverSpec(
            id: "com.nullmoth.NMXAudio",
            name: "NMXAudio",
            category: .audio,
            summary: "NVIDIA HDMI / 通用音频输出驱动（社区方案）。",
            repo: nil,
            homepage: nil,
            required: false,
            note: "本机已在使用；HDMI 音频随显卡驱动一起生效，升级显卡驱动时注意版本配套。"
        ),
        DriverSpec(
            id: "as.vit9696.AppleALC",
            name: "AppleALC",
            category: .audio,
            summary: "Realtek / Conexant / IDT 板载声卡驱动，配合 layout-id 出声。",
            repo: "acidanthera/AppleALC",
            homepage: "https://github.com/acidanthera/AppleALC/releases",
            required: false,
            note: "装好后需在 config.plist 的 DeviceProperties 给声卡注入 layout-id（如 ALC287 常用 21 / 11 / 69）。"
        ),
        DriverSpec(
            id: "as.vit9696.SMCLightSensor",
            name: "SMCLightSensor",
            category: .audio,
            summary: "环境光传感器模拟，影响自动亮度与键盘背光。",
            repo: "acidanthera/VirtualSMC",
            homepage: "https://github.com/acidanthera/VirtualSMC/releases",
            required: false,
            note: "属于 VirtualSMC 插件，需与 VirtualSMC 版本一致。"
        )
    ]

    // MARK: 网络
    static let network: [DriverSpec] = [
        DriverSpec(
            id: "com.insanelymac.RTL812xLucy",
            name: "LucyRTL8125",
            category: .network,
            summary: "Realtek 8125 / 8126 2.5G 有线网卡驱动（Lucy 版）。",
            repo: nil,
            homepage: "https://github.com/Mieze/LucyRTL8125Ethernet",
            required: false,
            note: "本机已在使用；与旧的 RealtekRTL8111 不能同时启用，会抢同一 PCI 设备。"
        ),
        DriverSpec(
            id: "com.insanelymac.RealtekRTL8111",
            name: "RealtekRTL8111",
            category: .network,
            summary: "Realtek 8168/8111 千兆有线网卡驱动（笔记本最常见）。",
            repo: nil,
            homepage: "https://github.com/Mieze/RTL8111_driver_for_OS_X/releases",
            required: false,
            note: "先确认芯片型号：`system_profiler SPEthernetDataType` 或 ioreg 里的 PCI 厂商 0x10EC。"
        ),
        DriverSpec(
            id: "com.insanelymac.IntelMausiEthernet",
            name: "IntelMausi",
            category: .network,
            summary: "Intel I219 / I225 系列有线网卡驱动。",
            repo: "acidanthera/IntelMausi",
            homepage: "https://github.com/acidanthera/IntelMausi/releases",
            required: false,
            note: "I225-V 需要额外 `dk.e1000=0` 或设备属性修补。"
        ),
        DriverSpec(
            id: "com.zxystd.AirportItlwm",
            name: "AirportItlwm",
            category: .network,
            summary: "Intel 无线网卡原生接口驱动（走系统 Wi-Fi 菜单，可隔空投送）。",
            repo: nil,
            homepage: "https://github.com/OpenIntelWireless/itlwm/releases",
            required: false,
            note: "必须下载与 macOS 大版本对应的分支；与 itlwm 二选一，不能同时装。"
        ),
        DriverSpec(
            id: "com.zxystd.itlwm",
            name: "itlwm",
            category: .network,
            summary: "Intel 无线网卡备选方案，需配合 HeliPort 客户端使用。",
            repo: nil,
            homepage: "https://github.com/OpenIntelWireless/itlwm/releases",
            required: false,
            note: "不支持隔空投送/接力，仅作为 AirportItlwm 不可用时的替代。"
        ),
        DriverSpec(
            id: "com.zxystd.IntelBluetoothFirmware",
            name: "IntelBluetoothFirmware",
            category: .network,
            summary: "Intel 蓝牙固件上传驱动。",
            repo: nil,
            homepage: "https://github.com/OpenIntelWireless/IntelBluetoothFirmware/releases",
            required: false,
            note: "macOS 12+ 必须同时装 BlueToolFixup，否则蓝牙无法打开。"
        ),
        DriverSpec(
            id: "com.zxystd.IntelBTPatcher",
            name: "IntelBTPatcher",
            category: .network,
            summary: "Intel 蓝牙补丁，配合固件上传驱动解决无法连接的问题。",
            repo: nil,
            homepage: "https://github.com/OpenIntelWireless/IntelBluetoothFirmware/releases",
            required: false,
            note: "与 IntelBluetoothFirmware、BlueToolFixup 三者成套使用。"
        ),
        DriverSpec(
            id: "com.zxystd.BlueToolFixup",
            name: "BlueToolFixup",
            category: .network,
            summary: "修补 macOS 12+ 的蓝牙协议栈，第三方蓝牙卡必需。",
            repo: nil,
            homepage: "https://github.com/acidanthera/BrcmPatchRAM/releases",
            required: false,
            note: "从 BrcmPatchRAM 发布包中提取；Intel/博通卡都需要。"
        ),
        DriverSpec(
            id: "as.acidanthera.BrcmPatchRAM3",
            name: "BrcmPatchRAM3",
            category: .network,
            summary: "博通蓝牙固件注入（BCM94352 / 94360 等）。",
            repo: "acidanthera/BrcmPatchRAM",
            homepage: "https://github.com/acidanthera/BrcmPatchRAM/releases",
            required: false,
            note: "按芯片选择 BrcmPatchRAM2（≤10.14）或 3（10.15+）。"
        )
    ]

    // MARK: 显卡
    static let graphics: [DriverSpec] = [
        DriverSpec(
            id: "org.b00t0x.WhateverXe",
            name: "WhateverXe",
            category: .graphics,
            summary: "Intel Xe 核显修补（11 代以后核显亮屏、硬解）。",
            repo: "b00t0x/WhateverXe",
            homepage: "https://github.com/b00t0x/WhateverXe/releases",
            required: false,
            note: "本机已在使用；需与 WhateverGreen 二选一，不能同时启用。"
        ),
        DriverSpec(
            id: "org.nullmoth.SMCNvidiaGPU",
            name: "SMCNvidiaGPU",
            category: .graphics,
            summary: "NVIDIA 显卡 SMC 传感器桥接，暴露 GPU 温度与频率。",
            repo: nil,
            homepage: nil,
            required: false,
            note: "必须与 NVRM 系列驱动同版本，否则会有加载顺序问题。"
        )
    ]

    // MARK: 存储与 USB
    static let storage: [DriverSpec] = [
        DriverSpec(
            id: "com.insanelymac.RealtekCardReader",
            name: "RealtekCardReader",
            category: .storage,
            summary: "Realtek 读卡器驱动（SD 卡槽）。",
            repo: nil,
            homepage: "https://github.com/0xFireWolf/RealtekCardReader",
            required: false,
            note: "需要同时装 RealtekCardReaderFriend 才能在侧边栏显示卷。"
        ),
        DriverSpec(
            id: "com.rehabman.driver.USBInjectAll",
            name: "USBInjectAll",
            category: .storage,
            summary: "为所有 USB 端口建端口表，便于定制 USBPorts。",
            repo: nil,
            homepage: "https://github.com/Sniki/OS-X-USB-Inject-All/releases",
            required: false,
            note: "仅用于调试；定制好 USBPorts.kext 后应移除，避免端口混乱。"
        ),
        DriverSpec(
            id: "com.dhinakg.USBToolBox",
            name: "USBToolBox",
            category: .storage,
            summary: "跨平台 USB 端口定制工具产出的 kext。",
            repo: nil,
            homepage: "https://github.com/USBToolBox/kext/releases",
            required: false,
            note: "需先用 USBToolBox 在 Windows/macOS 下导出 UTBMap.kext。"
        ),
        DriverSpec(
            id: "com.dhinakg.USBToolBox.injector",
            name: "UTBMap",
            category: .storage,
            summary: "USB 端口映射表，由 USBToolBox 生成，记录每个物理口的类型。",
            repo: nil,
            homepage: nil,
            required: false,
            note: "换机箱或改口后需要重新生成；Enable 状态跟随 USBToolBox。"
        ),
        DriverSpec(
            id: "org.rehabman.injector.XHCI.unsupported",
            name: "XHCI-unsupported",
            category: .storage,
            summary: "为系统未列出的 XHCI 控制器注入端口限制，解决 USB 口不识别。",
            repo: nil,
            homepage: nil,
            required: false,
            note: "只做端口数量修正；真正的端口映射仍需 USBPorts / UTBMap。"
        )
    ]

    // MARK: 笔记本
    static let laptop: [DriverSpec] = [
        DriverSpec(
            id: "as.vit9696.SMCBatteryManager",
            name: "SMCBatteryManager",
            category: .laptop,
            summary: "电池电量、充电状态、循环次数显示。",
            repo: "acidanthera/VirtualSMC",
            homepage: "https://github.com/acidanthera/VirtualSMC/releases",
            required: false,
            note: "多数笔记本只需它即可显示电量；小众 EC 需要 ECEnabler 或 ACPI 电池补丁。"
        ),
        DriverSpec(
            id: "as.vit9696.SMCSuperIO",
            name: "SMCSuperIO",
            category: .laptop,
            summary: "台式机 SuperIO 风扇/电压监控（笔记本 EC 不受支持）。",
            repo: "acidanthera/VirtualSMC",
            homepage: "https://github.com/acidanthera/VirtualSMC/releases",
            required: false,
            note: "笔记本风扇挂在 EC 上，本驱动读不到，属正常现象。"
        ),
        DriverSpec(
            id: "com.alexandred.VoodooI2C",
            name: "VoodooI2C",
            category: .laptop,
            summary: "I2C 触控板/触摸屏总线驱动。",
            repo: nil,
            homepage: "https://github.com/VoodooI2C/VoodooI2C/releases",
            required: false,
            note: "需要配套 VoodooI2CHID（触控板）或 VoodooI2CSynaptics，并做 ACPI 补丁。"
        ),
        DriverSpec(
            id: "com.alexandred.VoodooI2CHID",
            name: "VoodooI2CHID",
            category: .laptop,
            summary: "I2C HID 设备驱动，负责触控板多点手势。",
            repo: nil,
            homepage: "https://github.com/VoodooI2C/VoodooI2C/releases",
            required: false,
            note: "属于 VoodooI2C 发布包内的插件；与 VoodooInput 配合实现手势。"
        ),
        DriverSpec(
            id: "as.acidanthera.voodoo.driver.PS2Controller",
            name: "VoodooPS2Controller",
            category: .laptop,
            summary: "PS/2 键盘与触控板驱动（老式接口）。",
            repo: "acidanthera/VoodooPS2",
            homepage: "https://github.com/acidanthera/VoodooPS2/releases",
            required: false,
            note: "自带 Keyboard / Mouse / Trackpad 插件，需在 config 中一并启用。"
        ),
        DriverSpec(
            id: "as.acidanthera.BrightnessKeys",
            name: "BrightnessKeys",
            category: .laptop,
            summary: "让 F1/F2 等亮度键在 macOS 下生效。",
            repo: "acidanthera/BrightnessKeys",
            homepage: "https://github.com/acidanthera/BrightnessKeys/releases",
            required: false,
            note: "需要 ACPI 中存在 _Qxx 亮度事件；核显需先能调亮度。"
        )
    ]
}
