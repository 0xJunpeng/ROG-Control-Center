import Foundation
import IOKit

/// 功耗监测数据源
///
/// 本机（macOS 26）实测结论：
/// - AppleSMC 用户态接口被系统关闭，PK0/PK1 等 SMC 功耗键全部不可读；
/// - IOReport（GPU Stats / Energy Model）的符号在 macOS 26 的 IOKit 框架中已移除，
///   用户态无法枚举能量通道 → GPU 真实功耗读不到（NVIDIA NVRM 驱动也不提供统计）；
/// - CPU 封装 / 内存功耗由自研 kext NvFanProbe 在内核层读 RAPL 计数器并发布
///   （CPUPowerMW / DRAMPowerMW，需重启后生效）；
/// - 电池功率取自 IORegistry 的 AppleSmartBattery（Voltage mV × InstantAmperage mA）。
enum PowerMonitor {

    // MARK: - 电池 / 电源

    struct BatteryInfo {
        var watts: Double = 0        // 放电为正，充电为负，0 = 无电流
        var percent: Double = 0      // 0~100
        var charging: Bool = false
        var onAC: Bool = false
        var fullyCharged: Bool = false
        var cycleCount: Int = 0
        var tempC: Double = 0
        var designCapacity: Int = 0
        var maxCapacity: Int = 0
        var valid: Bool = false
    }

    /// 读取 AppleSmartBattery 的 IORegistry 属性（无需 root）
    static func readBattery() -> BatteryInfo {
        var info = BatteryInfo()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return info }
        defer { IOObjectRelease(service) }

        var rawProps: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &rawProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = rawProps?.takeRetainedValue() as? [String: Any] else { return info }

        let num = { (key: String) -> Double? in
            (props[key] as? NSNumber)?.doubleValue
        }
        let flag = { (key: String) -> Bool in
            (props[key] as? NSNumber)?.boolValue ?? false
        }

        let voltage = num("Voltage") ?? 0          // mV
        let current = num("InstantAmperage") ?? 0  // mA，放电为正
        info.watts = voltage > 0 ? voltage * current / 1_000_000.0 : 0

        let cur = num("AppleRawCurrentCapacity") ?? num("CurrentCapacity") ?? 0
        let maxCap = num("AppleRawMaxCapacity") ?? num("MaxCapacity") ?? 0
        if maxCap > 0 { info.percent = max(0, min(100, cur / maxCap * 100)) }

        info.charging = flag("IsCharging")
        info.onAC = flag("ExternalConnected")
        info.fullyCharged = flag("FullyCharged")
        info.cycleCount = Int(num("CycleCount") ?? 0)
        info.designCapacity = Int(num("DesignCapacity") ?? 0)
        info.maxCapacity = Int(maxCap)
        // 电池温度：0.1 K 单位
        if let t = num("Temperature"), t > 1500, t < 4000 {
            info.tempC = (t - 2731.5) / 10.0
        }
        info.valid = maxCap > 0
        return info
    }

    /// 电源状态文案
    static func powerStateText(_ b: BatteryInfo) -> String {
        if !b.valid { return "未检测到电池" }
        if b.onAC && b.fullyCharged { return "外接电源 · 已充满" }
        if b.onAC && b.charging { return "外接电源 · 充电中" }
        if b.onAC { return "外接电源" }
        return "使用电池"
    }
}
