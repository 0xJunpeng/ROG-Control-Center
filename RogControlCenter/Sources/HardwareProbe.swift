import Foundation

// MARK: - 硬件概览
struct HardwareInfo {
    var model: String = "—"
    var cpu: String = "—"
    var audio: String = "—"          // 声卡 codec
    var ethernet: String = "—"
    var wifi: String = "—"
    var bluetooth: String = "—"
    var gpu: String = "—"
    var hasAppleHDA: Bool = false
    var hasWiFiDriver: Bool = false
}

// MARK: - 硬件探测
//
// 全部走系统自带命令（ioreg / networksetup / system_profiler），
// 结果用于「驱动中心」推荐匹配的驱动，不做任何写操作。
enum HardwareProbe {

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func probe() -> HardwareInfo {
        var info = HardwareInfo()

        // 机型 / CPU
        info.model = run("/usr/sbin/sysctl", ["-n", "hw.model"]).trimmingCharacters(in: .whitespacesAndNewlines)
        var cpu = run("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if cpu.isEmpty { cpu = run("/usr/sbin/sysctl", ["-n", "hw.model"]).trimmingCharacters(in: .whitespacesAndNewlines) }
        info.cpu = cpu.isEmpty ? "—" : cpu

        // 声卡：HDA 控制器 + codec vendor
        let hda = run("/usr/sbin/ioreg", ["-w0", "-l", "-r", "-c", "AppleHDAController"])
        info.hasAppleHDA = !hda.isEmpty
        if let codec = parseCodec(hda) {
            info.audio = codec
        } else if info.hasAppleHDA {
            info.audio = "HDA 控制器已驱动"
        } else {
            info.audio = "未找到 HDA 设备"
        }

        // 有线网卡
        let ports = run("/usr/sbin/networksetup", ["-listallhardwareports"])
        info.ethernet = parseEthernet(ports)

        // 无线
        let air = run("/usr/sbin/system_profiler", ["SPAirPortDataType", "-detailLevel", "mini"])
        info.wifi = parseWiFi(air)
        info.hasWiFiDriver = !info.wifi.contains("未检测") && !info.wifi.isEmpty

        // 蓝牙
        let bt = run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-detailLevel", "mini"])
        info.bluetooth = parseBluetooth(bt)

        // 显卡
        let disp = run("/usr/sbin/system_profiler", ["SPDisplaysDataType", "-detailLevel", "mini"])
        info.gpu = parseGPU(disp)

        return info
    }

    // MARK: 解析
    private static func parseCodec(_ text: String) -> String? {
        // IOHDACodecVendorID = 283971207 (0x10EC0287)
        let patterns = ["IOHDACodecVendorID\" = (\\d+)", "IOHDACodecVendorID</key>\\s*<integer>(\\d+)"]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p),
               let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: text),
               let v = UInt32(text[r]) {
                return codecName(v)
            }
        }
        return nil
    }

    private static func codecName(_ vendor: UInt32) -> String {
        let v = vendor & 0xFFFF0000
        let id = vendor & 0x0000FFFF
        switch v {
        case 0x10EC0000: return String(format: "Realtek ALC%X", id)   // 0x10EC0287 → ALC287
        case 0x80860000: return String(format: "Intel HDMI (0x%04X)", id)
        case 0x10020000: return String(format: "IDT/Conexant (0x%04X)", id)
        case 0x14F10000: return String(format: "Cirrus (0x%04X)", id)
        default:         return String(format: "HDA Codec 0x%08X", vendor)
        }
    }

    private static func parseEthernet(_ text: String) -> String {
        var port = ""
        var dev = ""
        var mac = ""
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("Hardware Port:") {
                port = String(s.dropFirst("Hardware Port:".count)).trimmingCharacters(in: .whitespaces)
            } else if s.hasPrefix("Device:") {
                dev = String(s.dropFirst("Device:".count)).trimmingCharacters(in: .whitespaces)
            } else if s.hasPrefix("Ethernet Address:") {
                mac = String(s.dropFirst("Ethernet Address:".count)).trimmingCharacters(in: .whitespaces)
                if !port.isEmpty, !port.contains("Wi-Fi"), !port.contains("Thunderbolt") {
                    return "\(dev) · \(port)" + (mac.isEmpty ? "" : " · \(mac)")
                }
            }
        }
        return "未检测到有线网卡"
    }

    private static func parseWiFi(_ text: String) -> String {
        if text.contains("Card Type:") {
            for line in text.split(separator: "\n") {
                let s = line.trimmingCharacters(in: .whitespaces)
                if s.hasPrefix("Card Type:") {
                    return String(s.dropFirst("Card Type:".count)).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        if text.contains("AirPort") || text.contains("en0") {
            return "Wi-Fi 接口存在（未取到型号）"
        }
        return "未检测到无线网卡"
    }

    private static func parseBluetooth(_ text: String) -> String {
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("Chipset:") || s.hasPrefix("Bluetooth Low Energy Supported") {
                if s.hasPrefix("Chipset:") {
                    return String(s.dropFirst("Chipset:".count)).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        if text.contains("Bluetooth") { return "控制器存在" }
        return "未检测到蓝牙"
    }

    private static func parseGPU(_ text: String) -> String {
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("Chipset Model:") {
                return String(s.dropFirst("Chipset Model:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return "—"
    }
}
