import Foundation

/// 系统资源监控：CPU / 内存 / 磁盘 / 网络，每 2 秒采样一次
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published var cpuUsage: Double = 0        // %
    @Published var ramUsage: Double = 0        // %
    @Published var diskUsage: Double = 0       // %
    @Published var upSpeed: Double = 0         // bytes/s
    @Published var downSpeed: Double = 0       // bytes/s
    @Published var cpuTemp: Double = 0         // °C (SMC / 内核传感器)
    @Published var tempSource: String = "不可用"  // 温度数据来源
    @Published var fanRPM: [Double] = []       // 各风扇转速 (SMC)
    @Published var cpuPowerW: Double = 0       // CPU 封装功耗 (RAPL, kext)
    @Published var dramPowerW: Double = 0      // 内存功耗 (RAPL, kext)
    @Published var gpuPowerW: Double = 0       // GPU 功耗（macOS 26 无数据源，恒 0）
    @Published var battWatts: Double = 0       // 电池功率：放电为正 / 充电为负
    @Published var battPercent: Double = 0     // 电量 %
    @Published var battCharging: Bool = false
    @Published var battOnAC: Bool = true
    @Published var battCycles: Int = 0
    @Published var battValid: Bool = false
    @Published var histPower: [Double] = Array(repeating: 8, count: 60)
    @Published var histCPU: [Double] = Array(repeating: 5, count: 60)
    @Published var histTemp: [Double] = Array(repeating: 45, count: 60)

    private var prevCPU: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64, total: UInt64)?
    private var prevNet: (rx: UInt64, tx: UInt64, t: Date)?
    private var timer: Timer?
    private var smcAvailable = false

    private init() {
        smcAvailable = SMC.shared.available
        let saved = UserDefaults.standard.double(forKey: "app.refreshInterval")
        interval = saved > 0.2 ? saved : 2.0
        sample()
        startTimer()
    }

    var hasSMC: Bool { smcAvailable }

    /// 采样间隔（秒），可由设置页调整
    private var interval: Double = 2.0

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func setInterval(_ v: Double) {
        guard v > 0.2 else { return }
        interval = v
        UserDefaults.standard.set(v, forKey: "app.refreshInterval")
        startTimer()
    }

    private func sample() {
        sampleCPU()
        sampleRAM()
        sampleDisk()
        sampleNet()
        sampleSMC()
        samplePower()
        histCPU.append(cpuUsage);  if histCPU.count  > 60 { histCPU.removeFirst(histCPU.count - 60) }
        histTemp.append(cpuTemp);  if histTemp.count > 60 { histTemp.removeFirst(histTemp.count - 60) }
        histPower.append(max(0, cpuPowerW)); if histPower.count > 60 { histPower.removeFirst(histPower.count - 60) }
    }

    // MARK: - CPU（host_processor_info）
    private func sampleCPU() {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var msgCount: mach_msg_type_number_t = 0
        let host = mach_host_self()
        let err = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &msgCount)
        guard err == KERN_SUCCESS, let info = info else { return }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(msgCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        var user: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0
        for i in 0..<Int(cpuCount) {
            let base = i * Int(CPU_STATE_MAX)
            user   += UInt64(info[base + Int(CPU_STATE_USER)])
            system += UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            idle   += UInt64(info[base + Int(CPU_STATE_IDLE)])
            nice   += UInt64(info[base + Int(CPU_STATE_NICE)])
        }
        let total = user + system + idle + nice
        if let prev = prevCPU, total > prev.total {
            let dt = Double(total - prev.total)
            let busy = Double((user &- prev.user) + (system &- prev.system) + (nice &- prev.nice))
            cpuUsage = max(0, min(100, busy / dt * 100))
        }
        prevCPU = (user, system, idle, nice, total)
    }

    // MARK: - 内存（host_statistics64）
    private func sampleRAM() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let err = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard err == KERN_SUCCESS else { return }
        var total: UInt64 = 0
        var sizeLen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &sizeLen, nil, 0)
        guard total > 0 else { return }
        let pageSize = UInt64(vm_kernel_page_size)
        let freeBytes = UInt64(stats.free_count + stats.inactive_count
                               + stats.purgeable_count + stats.speculative_count) * pageSize
        let used = total &- min(freeBytes, total)
        ramUsage = max(0, min(100, Double(used) / Double(total) * 100))
    }

    // MARK: - 磁盘（statfs）
    private func sampleDisk() {
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { return }
        let total = UInt64(fs.f_blocks) * UInt64(fs.f_bsize)
        let avail = UInt64(fs.f_bavail) * UInt64(fs.f_bsize)
        guard total > 0 else { return }
        diskUsage = Double(total - avail) / Double(total) * 100
    }

    // MARK: - 网络（sysctl NET_RT_IFLIST2）
    //
    // if_msghdr 的真实布局是：ifm_msglen(UInt16) + ifm_version(UInt8) + ifm_type(UInt8)，
    // 所以 type 在偏移 3、长度在偏移 0..1。且结构体要求 8 字节对齐，
    // 这里统一用 memcpy 拷贝，避免非对齐 load 导致的崩溃或读到脏数据。
    private func networkBytes() -> (rx: UInt64, tx: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: Int = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return nil }

        var rx: UInt64 = 0, tx: UInt64 = 0
        let hdrSize = MemoryLayout<if_msghdr2>.size
        let sdlSize = MemoryLayout<sockaddr_dl>.size

        buf.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + hdrSize <= len {
                var hdr = if_msghdr2()
                memcpy(&hdr, base.advanced(by: offset), hdrSize)

                let msgLen = Int(hdr.ifm_msglen)
                if msgLen <= 0 { break }

                if Int32(hdr.ifm_type) == RTM_IFINFO2 {
                    // 紧跟其后的 sockaddr_dl 里有接口名
                    var name = ""
                    let sdlOff = offset + hdrSize
                    if sdlOff + sdlSize <= len {
                        var sdl = sockaddr_dl()
                        memcpy(&sdl, base.advanced(by: sdlOff), sdlSize)
                        let nlen = Int(sdl.sdl_nlen)
                        if nlen > 0 && nlen <= 12 {
                            let dataOff = sdlOff + MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)!
                            name = String(bytes: UnsafeRawBufferPointer(start: base.advanced(by: dataOff), count: nlen),
                                          encoding: .utf8) ?? ""
                        }
                    }
                    let isLoopback = Int32(hdr.ifm_data.ifi_type) == IFT_LOOP
                    // awdl / llw 是 Apple 无线直连，与 en0 重复计数
                    let isDuplicate = name.hasPrefix("awdl") || name.hasPrefix("llw")
                    if !isLoopback && !isDuplicate {
                        rx &+= hdr.ifm_data.ifi_ibytes
                        tx &+= hdr.ifm_data.ifi_obytes
                    }
                }
                offset += msgLen
            }
        }
        return (rx, tx)
    }

    private func sampleNet() {
        guard let cur = networkBytes() else { return }
        if let prev = prevNet {
            let dt = Date().timeIntervalSince(prev.t)
            if dt > 0.5 {
                downSpeed = cur.rx >= prev.rx ? Double(cur.rx &- prev.rx) / dt : 0
                upSpeed   = cur.tx >= prev.tx ? Double(cur.tx &- prev.tx) / dt : 0
            }
        }
        prevNet = (cur.rx, cur.tx, Date())
    }

    // MARK: - SMC 传感器（温度 / 风扇）
    //
    // 优先走 SMC（真机/受支持机型）；macOS 26 上第三方进程无法访问 AppleSMC，
    // 温度回退到自研内核传感器（MSR 0x1B1）。
    private func sampleSMC() {
        let smc = SMC.shared
        let smcTemp = smc.readCPUTemperature()
        cpuTemp = smcTemp > 0 ? smcTemp : KextSensors.cpuTemperature()
        fanRPM = smc.readFanSpeeds()
        tempSource = smcTemp > 0 ? "SMC" : (cpuTemp > 0 ? "内核传感器" : "不可用")
    }

    // MARK: - 功耗（kext RAPL + 电池）
    private func samplePower() {
        cpuPowerW = KextSensors.cpuPower()
        dramPowerW = KextSensors.dramPower()

        let b = PowerMonitor.readBattery()
        battWatts = b.watts
        battPercent = b.percent
        battCharging = b.charging
        battOnAC = b.onAC
        battCycles = b.cycleCount
        battValid = b.valid
    }

    /// 功耗数据来源说明
    var powerSourceText: String {
        if cpuPowerW > 0 { return "kext RAPL + 电池" }
        if battValid { return "电池（CPU 功耗需重启生效）" }
        return "不可用"
    }

    /// 电源状态文案
    var powerStateText: String {
        if !battValid { return "未检测到电池" }
        if battOnAC && battPercent >= 99.5 { return "外接电源 · 已充满" }
        if battOnAC && battCharging { return "外接电源 · 充电中" }
        if battOnAC { return "外接电源" }
        return "使用电池"
    }

    /// 电池功率详情（放电为正，充电为负）
    var battDetailText: String {
        guard battValid else { return "—" }
        if battWatts > 0.3 { return String(format: "放电 %.1f W", battWatts) }
        if battWatts < -0.3 { return String(format: "充电 %.1f W", -battWatts) }
        return "0 W（待机）"
    }

    // MARK: - 格式化辅助
    /// 状态栏用的极简速度文本：0 / 340K / 1.2M / 2.5G
    static func compactSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_073_741_824 { return String(format: "%.1fG", bytesPerSec / 1_073_741_824) }
        if bytesPerSec >= 1_048_576 { return String(format: "%.1fM", bytesPerSec / 1_048_576) }
        if bytesPerSec >= 1024 { return String(format: "%.0fK", bytesPerSec / 1024) }
        return "0"
    }

    static func speedText(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1024 * 1024 { return String(format: "%.1f MB/s", bytesPerSec / 1048576) }
        if bytesPerSec >= 1024 { return String(format: "%.0f KB/s", bytesPerSec / 1024) }
        return String(format: "%.0f B/s", bytesPerSec)
    }
}
