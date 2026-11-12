import Foundation
import IOKit

/// 从自定义传感器 kext（NvFanProbe）读取内核层采集的 CPU 温度。
///
/// 背景：macOS 26 起 AppleSMC 的用户态私有接口对第三方进程一律返回
/// kIOReturnBadArgument，SMCProcessor 插件在这台机器上也没有挂载，
/// 因此温度只能由内核态 kext 通过 MSR 读取，并以 IORegistry 属性发布。
enum KextSensors {

    private static func service() -> io_object_t {
        // 常规路径：IOService 匹配（kext 调用了 registerService() 时可用）
        var it: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("NvFanProbe"), &it) == KERN_SUCCESS {
            let e = IOIteratorNext(it)
            IOObjectRelease(it)
            if e != 0 { return e }
        }
        // 兜底路径：0.4 版 kext 未调用 registerService()，匹配不到，
        // 但 registry 节点仍挂在 IOResources 下，按路径直接取句柄即可
        let path = "IOService:/IOResources/NvFanProbe"
        return IORegistryEntryFromPath(kIOMainPortDefault, path.cString(using: .utf8)!)
    }

    private static func number(_ entry: io_object_t, _ key: String) -> Double? {
        guard let prop = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return (prop.takeRetainedValue() as? NSNumber)?.doubleValue
    }

    /// 是否已加载传感器 kext
    static var isAvailable: Bool {
        let s = service()
        guard s != 0 else { return false }
        IOObjectRelease(s)
        return true
    }

    /// CPU 封装温度（°C），0 表示不可用
    static func cpuTemperature() -> Double {
        let s = service()
        guard s != 0 else { return 0 }
        defer { IOObjectRelease(s) }
        guard let t = number(s, "CPUTempC"), t > 1, t < 130 else { return 0 }
        return t
    }

    /// CPU 封装功耗（W），0 表示不可用（kext 0.5+ 通过 RAPL 发布，重启后生效）
    static func cpuPower() -> Double {
        let s = service()
        guard s != 0 else { return 0 }
        defer { IOObjectRelease(s) }
        guard let mw = number(s, "CPUPowerMW"), mw >= 0, mw < 500_000 else { return 0 }
        return mw / 1000.0
    }

    /// 内存（DRAM）功耗（W），0 表示不可用或平台不提供
    static func dramPower() -> Double {
        let s = service()
        guard s != 0 else { return 0 }
        defer { IOObjectRelease(s) }
        guard let mw = number(s, "DRAMPowerMW"), mw >= 0, mw < 200_000 else { return 0 }
        return mw / 1000.0
    }

    /// 温度数据来源说明（用于界面提示）
    static var sourceDescription: String {
        isAvailable ? "内核传感器 (MSR)" : "不可用"
    }
}
