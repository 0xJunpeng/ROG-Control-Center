import Foundation
import IOKit

/// SMC 用户态读取（温度、风扇转速），参考公开的 AppleSMC 用户客户端协议
final class SMC {
    static let shared = SMC()
    private var conn: io_connect_t = 0
    private(set) var available = false

    // 用户客户端选择器（固定为 2 = KERNEL_INDEX_SMC，命令通过 data8 传递）
    private let SEL_SMC: UInt32 = 2
    // data8 命令
    private let CMD_READ_BYTES: UInt8 = 5
    private let CMD_READ_KEYINDEX: UInt8 = 8
    private let CMD_READ_KEYINFO: UInt8 = 9

    struct SMCVersion {
        var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0
        var reserved: UInt8 = 0; var release: UInt16 = 0
    }
    struct SMCPLimitData {
        var version: UInt16 = 0; var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0
    }
    struct SMCKeyInfoData {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
    struct UInt8x32 {
        var v: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
                = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }
    struct SMCKeyData {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0     // macOS 26 (Tahoe) AppleSMCClient 新增字段，结构体从 76 → 80 字节
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes = UInt8x32()
    }

    private init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        available = (kr == KERN_SUCCESS)
    }

    deinit {
        if available { IOServiceClose(conn) }
    }

    private func call(_ input: inout SMCKeyData, _ output: inout SMCKeyData, selector: UInt32) -> kern_return_t {
        var inSize = MemoryLayout<SMCKeyData>.stride
        var outSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(conn, selector, &input, inSize, &output, &outSize)
    }

    private func keyToInt(_ key: String) -> UInt32 {
        key.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1.asciiValue ?? 32) }
    }

    /// 读取一个 SMC 键，返回 (类型, 字节)
    func readValue(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard available else { return nil }
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = keyToInt(key)
        input.data8 = CMD_READ_KEYINFO
        guard call(&input, &output, selector: SEL_SMC) == KERN_SUCCESS else { return nil }
        let dataSize = Int(output.keyInfo.dataSize)
        guard dataSize > 0, dataSize <= 32 else { return nil }
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = CMD_READ_BYTES
        guard call(&input, &output, selector: SEL_SMC) == KERN_SUCCESS else { return nil }
        var bytes: [UInt8] = []
        withUnsafeBytes(of: output.bytes) { buf in
            bytes = Array(buf.prefix(dataSize))
        }
        let typeLE = withUnsafeBytes(of: output.keyInfo.dataType) { Array($0) }
        let typeBE = String(bytes: typeLE.reversed(), encoding: .ascii) ?? ""
        return (typeBE, bytes)
    }

    /// 将 SMC 原始字节转换为数值
    private func toDouble(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt " where bytes.count == 4:
            let raw = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            return Double(Float(bitPattern: raw))
        case "sp78" where bytes.count == 2:
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256.0
        case "fpe2" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        case "sp87" where bytes.count == 2:
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256.0
        case "ui8" where !bytes.isEmpty:
            return Double(bytes[0])
        case "ui16" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default:
            return nil
        }
    }

    func read(_ key: String) -> Double? {
        guard let (type, bytes) = readValue(key) else { return nil }
        return toDouble(type: type, bytes: bytes)
    }

    /// 枚举设备上实际存在的全部 SMC 键（黑苹果 VirtualSMC 可能只暴露部分键）
    private lazy var allKeys: [String: String] = {
        guard available else { return [:] }
        var map: [String: String] = [:]
        // 键总数：读取 "#KEY" 键
        guard let n = read("#KEY"), n > 0, n < 10000 else { return map }
        for i in 0..<Int(n) {
            var inp = SMCKeyData()
            var out = SMCKeyData()
            inp.data8 = CMD_READ_KEYINDEX
            inp.data32 = UInt32(i)
            guard call(&inp, &out, selector: SEL_SMC) == KERN_SUCCESS else { continue }
            var chars: [UInt8] = []
            withUnsafeBytes(of: out.key.bigEndian) { chars = Array($0) }
            guard let key = String(bytes: chars, encoding: .ascii),
                  key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "#" || $0 == "$" || $0 == "!" || $0 == "%" }) else { continue }
            // 查询类型
            var i2 = SMCKeyData()
            var o2 = SMCKeyData()
            i2.key = keyToInt(key)
            i2.data8 = CMD_READ_KEYINFO
            if call(&i2, &o2, selector: SEL_SMC) == KERN_SUCCESS {
                let tLE = withUnsafeBytes(of: o2.keyInfo.dataType) { Array($0) }
                let t = String(bytes: tLE.reversed(), encoding: .ascii) ?? ""
                map[key] = t
            }
        }
        return map
    }()

    /// 诊断用：返回设备当前可见的全部键（键 → 类型）
    func dumpKeys() -> [String: String] { allKeys }

    /// 扫描键表中可用的温度键（类型 sp78 / flt ），按名称优先级排序
    private func temperatureKeyCandidates() -> [String] {
        let priority = ["TC0P", "TC0D", "TC0E", "TC0F", "TCAD", "TCGC", "TCXC", "Ta0P"]
        let keys = allKeys.filter { key, type in
            guard type == "sp78" || type == "flt " else { return false }
            return key.hasPrefix("T") || key.hasPrefix("t")
        }.map { $0.key }
        let sorted = priority.filter { keys.contains($0) }
        let rest = keys.filter { !sorted.contains($0) }.sorted()
        return sorted + rest
    }

    /// 扫描键表中的风扇转速键（FxAx / 实际转速）
    private func fanSpeedKeys() -> [String] {
        allKeys.compactMap { key, type in
            guard type == "fpe2" else { return nil }
            guard key.count == 4, key.hasPrefix("F"), key.hasSuffix("Ac") || key.hasSuffix("ac") else { return nil }
            return key
        }
        .sorted()
    }

    /// CPU 温度：优先标准键，否则全键扫描（适配 VirtualSMC/黑苹果）
    func readCPUTemperature() -> Double {
        // 1) 标准候选键快速路径
        for key in ["TC0P", "TC0D", "TC0E", "TC0F", "TCAD", "TCGC", "TCXC", "Ta0P"] {
            if let v = read(key), v > 5, v < 120 { return v }
        }
        // 2) 全键扫描
        for key in temperatureKeyCandidates() {
            if let v = read(key), v > 5, v < 120 { return v }
        }
        return 0
    }

    /// 全部风扇转速（含全键扫描回退）
    func readFanSpeeds() -> [Double] {
        var result: [Double] = []
        if let n = read("FNum"), n > 0 {
            for i in 0..<min(Int(n), 4) {
                if let v = read(String(format: "F%dAc", i)), v > 0 { result.append(v) }
            }
        }
        if result.isEmpty {
            for key in fanSpeedKeys() {
                if let v = read(key), v > 50, v < 20000 { result.append(v) }
                if result.count >= 4 { break }
            }
        }
        return result
    }
}
