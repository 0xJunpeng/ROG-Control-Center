import Foundation
import IOKit

/// 从自定义传感器 kext（NvFanProbe）读取内核层采集的 CPU 温度。
///
/// 背景：macOS 26 起 AppleSMC 的用户态私有接口对第三方进程一律返回
/// kIOReturnBadArgument，SMCProcessor 插件在这台机器上也没有挂载，
/// 因此温度只能由内核态 kext 通过 MSR 读取，并以 IORegistry 属性发布。
enum KextSensors {

    private static func service() -> io_object_t {
        IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("NvFanProbe"))
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

    /// 温度数据来源说明（用于界面提示）
    static var sourceDescription: String {
        isAvailable ? "内核传感器 (MSR)" : "不可用"
    }
}
