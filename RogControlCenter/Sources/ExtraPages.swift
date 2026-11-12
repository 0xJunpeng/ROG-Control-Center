import SwiftUI
import AppKit
import ServiceManagement

// MARK: - 性能与风扇
struct PerformancePage: View {
    @ObservedObject var m = SystemMonitor.shared
    @AppStorage("perf.mode") private var mode = 2

    private let modes: [(String, String, String, String)] = [
        ("moon.fill", "安静", "低转速 · 静音优先", "适合办公、夜间使用"),
        ("circle.lefthalf.filled", "均衡", "按温度线性提速", "日常使用的默认档"),
        ("flame.fill", "性能", "风扇提前拉满", "游戏、渲染、编译")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                RingView(value: m.cpuTemp / 100,
                         color: m.cpuTemp > 85 ? AppTheme.rogRed : AppTheme.orange,
                         text: m.cpuTemp > 0 ? String(format: "%.0f", m.cpuTemp) : "—",
                         sub: "°C", title: "CPU 温度")
                RingView(value: (m.fanRPM.first ?? 0) / 6000,
                         color: AppTheme.blue,
                         text: m.fanRPM.isEmpty ? "—" : String(format: "%.0f", m.fanRPM[0]),
                         sub: "RPM", title: "风扇转速")
                RingView(value: m.cpuUsage / 100, color: AppTheme.cyan,
                         text: String(format: "%.0f", m.cpuUsage), sub: "%", title: "CPU 负载")
                VStack(alignment: .leading, spacing: 8) {
                    Text("数据来源").font(.system(size: 11)).foregroundColor(.gray)
                    Text(m.tempSource)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(m.cpuTemp > 0 ? AppTheme.green : AppTheme.rogRed)
                    Text(m.cpuTemp > 0
                         ? "温度通道正常，曲线为实时采样。"
                         : "温度不可用：请在「驱动中心」确认 VirtualSMC 已启用，或重启后观察内核传感器。")
                        .font(.system(size: 10.5))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            PanelCard(title: "功耗监测", meta: m.powerSourceText) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        powerTile("CPU 封装",
                                  m.cpuPowerW > 0 ? String(format: "%.1f W", m.cpuPowerW) : "待重启生效",
                                  m.cpuPowerW > 45 ? AppTheme.rogRed : AppTheme.orange,
                                  "bolt.fill")
                        powerTile("内存 (DRAM)",
                                  m.dramPowerW > 0 ? String(format: "%.1f W", m.dramPowerW) : "平台不提供",
                                  AppTheme.blue,
                                  "memorychip")
                        powerTile("显卡",
                                  "驱动不提供",
                                  .gray,
                                  "display")
                        powerTile("电池",
                                  bText,
                                  battColor,
                                  m.battOnAC ? "powerplug.fill" : "battery.75percent")
                    }
                    if m.cpuPowerW > 0 {
                        Text("CPU 功耗曲线").font(.system(size: 10.5)).foregroundColor(.gray)
                        Sparkline(data: m.histPower, color: AppTheme.orange, range: 0...50)
                            .frame(height: 70)
                    }
                    if m.battValid {
                        VStack(alignment: .leading, spacing: 6) {
                            perfInfoRow("电源状态", m.powerStateText)
                            perfInfoRow("当前功率", m.battDetailText)
                            perfInfoRow("电量", String(format: "%.0f%%", m.battPercent))
                            perfInfoRow("循环次数", "\(m.battCycles) 次")
                        }
                        .padding(.top, 2)
                    }
                }
            }

            PanelCard(title: "性能模式", meta: "记录偏好 · 不改硬件") {
                HStack(spacing: 12) {
                    ForEach(Array(modes.enumerated()), id: \.offset) { i, item in
                        modeCard(i, icon: item.0, name: item.1, desc: item.2, hint: item.3)
                    }
                }
                Text("当前版本不写入 EC 寄存器：模式仅作为记录与风扇曲线参考，实际转速由固件控制。")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            PanelCard(title: "温度曲线", meta: "60 点 · 实时") {
                Sparkline(data: m.histTemp, color: AppTheme.orange, range: 30...100)
                    .frame(height: 100)
            }

            PanelCard(title: "风扇通道", meta: m.fanRPM.isEmpty ? "不可用" : "\(m.fanRPM.count) 路") {
                VStack(alignment: .leading, spacing: 8) {
                    if m.fanRPM.isEmpty {
                        Text("笔记本风扇挂在 EC（嵌入式控制器）上，SMCSuperIO 只支持台式机 SuperIO 芯片，因此读不到转速。")
                            .font(.system(size: 11.5)).foregroundColor(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("要读取需要针对本机 EC 寄存器单独写驱动：先用探测 kext 批量 dump 0x00~0xFF 区间，再从中定位转速寄存器。")
                            .font(.system(size: 11)).foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(Array(m.fanRPM.enumerated()), id: \.offset) { i, rpm in
                            HStack {
                                Text(i == 0 ? "主风扇" : "风扇 \(i + 1)")
                                    .font(.system(size: 12)).foregroundColor(.gray)
                                Spacer()
                                Text(String(format: "%.0f RPM", rpm))
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(AppTheme.blue)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 功耗文案与颜色
    private var bText: String {
        if !m.battValid { return "无电池" }
        if m.battWatts > 0.3 { return String(format: "%.1f W", m.battWatts) }
        if m.battWatts < -0.3 { return String(format: "-%.1f W", m.battWatts) }
        return "待机"
    }
    private var battColor: Color {
        if !m.battValid { return .gray }
        if !m.battOnAC && m.battPercent < 20 { return AppTheme.rogRed }
        return m.battOnAC ? AppTheme.green : AppTheme.orange
    }

    // MARK: 功耗小方格
    private func powerTile(_ name: String, _ value: String, _ color: Color, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(name).font(.system(size: 11))
            }
            .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundColor(value == "驱动不提供" || value == "平台不提供" || value == "无电池" ? .gray : color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.045)))
    }

    private func perfInfoRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 11.5)).foregroundColor(.gray).frame(width: 70, alignment: .leading)
            Text(v).font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func modeCard(_ idx: Int, icon: String, name: String, desc: String, hint: String) -> some View {
        let active = mode == idx
        return VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 20))
            Text(name).font(.system(size: 14, weight: .bold))
            Text(desc).font(.system(size: 10)).foregroundColor(.gray)
            Text(hint).font(.system(size: 9)).foregroundColor(.gray.opacity(0.7))
        }
        .foregroundColor(active ? AppTheme.rogRed : .white.opacity(0.6))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            CutCornerRect(cut: 12)
                .fill(active
                      ? AnyShapeStyle(LinearGradient(colors: [AppTheme.rogRed.opacity(0.16), AppTheme.rogRed.opacity(0.03)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.white.opacity(0.04)))
                .overlay(CutCornerRect(cut: 12).stroke(active ? AppTheme.rogRed : Color.white.opacity(0.1), lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture { mode = idx }
    }
}

// MARK: - 菜单栏
struct MenuBarPage: View {
    @AppStorage("mb.showCPU") private var showCPU = true
    @AppStorage("mb.showRAM") private var showRAM = true
    @AppStorage("mb.showSSD") private var showSSD = true
    @AppStorage("mb.showNet") private var showNet = true
    @AppStorage("mb.showPWR") private var showPWR = false
    @State private var launchAtLogin = SMAppServiceCheck.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelCard(title: "实时预览", meta: "跟随系统外观") {
                VStack(spacing: 10) {
                    preview(dark: true)
                    preview(dark: false)
                }
                Text("菜单栏宽度会随显示项自动收窄，数值变化时保持居中不跳动。")
                    .font(.system(size: 10.5)).foregroundColor(.gray)
            }

            PanelCard(title: "显示项", meta: "即时生效") {
                VStack(spacing: 2) {
                    toggleRow("CPU 占用", "cpu", $showCPU)
                    toggleRow("内存占用", "memorychip", $showRAM)
                    toggleRow("磁盘占用", "internaldrive", $showSSD)
                    toggleRow("网络上下行", "arrow.up.arrow.down", $showNet)
                    toggleRow("功耗 PWR", "bolt", $showPWR)
                }
            }

            PanelCard(title: "行为", meta: "") {
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开机自动启动").font(.system(size: 12.5)).foregroundColor(.white)
                        Text("登录后静默驻留菜单栏，不显示 Dock 图标").font(.system(size: 10.5)).foregroundColor(.gray)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: launchAtLogin) { _, v in SMAppServiceCheck.setEnabled(v) }
            }
        }
    }

    private func preview(dark: Bool) -> some View {
        HStack {
            Spacer()
            StatusBarView()
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color(white: 0.96))
                .environment(\.colorScheme, dark ? .dark : .light)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 7).fill(dark ? Color.black.opacity(0.35) : Color.white.opacity(0.75)))
    }

    private func toggleRow(_ title: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(.gray).frame(width: 18)
            Text(title).font(.system(size: 12.5)).foregroundColor(.white.opacity(0.85))
            Spacer()
            Toggle("", isOn: binding).toggleStyle(.switch).controlSize(.mini).labelsHidden()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
    }
}

// MARK: - 高级
struct AdvancedPage: View {
    @ObservedObject var m = SystemMonitor.shared
    @ObservedObject private var dm = DriverManager.shared
    @State private var report: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelCard(title: "内核与启动", meta: "只读") {
                VStack(spacing: 6) {
                    infoRow("机型标识", sysctl("hw.model"))
                    infoRow("处理器", sysctl("machdep.cpu.brand_string"))
                    infoRow("内核版本", Self.kernelVersion)
                    infoRow("内核架构", sysctl("hw.optional.arm64").isEmpty ? "x86_64" : "arm64")
                    infoRow("启动参数", nvram("boot-args").isEmpty ? "（无）" : nvram("boot-args"))
                }
            }

            PanelCard(title: "驱动状态", meta: dm.isEFIMounted ? "EFI 已挂载" : "EFI 未挂载") {
                HStack(spacing: 14) {
                    miniStat("EFI 驱动", "\(dm.kexts.count)", AppTheme.blue)
                    miniStat("已启用", "\(dm.kexts.filter(\.enabled).count)", AppTheme.green)
                    miniStat("内核加载", "\(DriverManager.kextstat().count)", AppTheme.cyan)
                    miniStat("待重启", dm.needsRestart ? "是" : "否", dm.needsRestart ? AppTheme.orange : .gray)
                }
                HStack(spacing: 10) {
                    Button("刷新驱动状态") { dm.refresh() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.blue.opacity(0.3)))
                }
            }

            PanelCard(title: "传感器通道", meta: m.tempSource) {
                VStack(spacing: 6) {
                    infoRow("SMC 用户客户端", m.hasSMC ? "可用" : "被系统拒绝")
                    infoRow("温度来源", m.tempSource)
                    infoRow("风扇通道", m.fanRPM.isEmpty ? "不可用（EC）" : "\(m.fanRPM.count) 路")
                    infoRow("功耗通道", m.cpuPowerW > 0 ? "RAPL（kext 0.5）" : "等待 kext 0.5 重启生效")
                    infoRow("电池通道", m.battValid ? "AppleSmartBattery" : "未检测到")
                }
            }

            PanelCard(title: "诊断", meta: "") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            report = Diagnostics.build()
                        } label: {
                            Text("生成诊断报告")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.rogRed.opacity(0.75)))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Diagnostics.save(report ?? Diagnostics.build())
                        } label: {
                            Text("保存到桌面")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(AppTheme.blue)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.blue.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    if let r = report {
                        ScrollView {
                            Text(r)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 140)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.35)))
                    }
                }
            }
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 11.5)).foregroundColor(.gray).frame(width: 90, alignment: .leading)
            Text(v.isEmpty ? "—" : v)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundColor(color)
            Text(label).font(.system(size: 10)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
    }

    private func sysctl(_ key: String) -> String {
        HardwareProbe.run("/usr/sbin/sysctl", ["-n", key]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nvram(_ key: String) -> String {
        let out = HardwareProbe.run("/usr/sbin/nvram", [key])
        // 输出形如 "boot-args\t-ctrsmt"
        if let tab = out.firstIndex(of: "\t") {
            return String(out[out.index(after: tab)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    static var kernelVersion: String {
        HardwareProbe.run("/usr/bin/uname", ["-a"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 设置
struct SettingsPage: View {
    @AppStorage("app.refreshInterval") private var interval: Double = 2
    @AppStorage("app.launchAtLogin") private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelCard(title: "监控", meta: "即时生效") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("采样间隔").font(.system(size: 12.5)).foregroundColor(.white)
                            Text("越小越灵敏，CPU 占用略高").font(.system(size: 10.5)).foregroundColor(.gray)
                        }
                        Spacer()
                        Picker("", selection: $interval) {
                            Text("1 秒").tag(1.0)
                            Text("2 秒").tag(2.0)
                            Text("5 秒").tag(5.0)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                        .onChange(of: interval) { _, v in
                            SystemMonitor.shared.setInterval(v)
                        }
                    }
                    Divider().overlay(Color.white.opacity(0.07))
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("开机自启动").font(.system(size: 12.5)).foregroundColor(.white)
                            Text("通过 SMAppService 注册登录项").font(.system(size: 10.5)).foregroundColor(.gray)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { SMAppServiceCheck.isEnabled },
                            set: { SMAppServiceCheck.setEnabled($0); launchAtLogin = $0 }
                        ))
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                }
            }

            PanelCard(title: "维护", meta: "") {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        DriverManager.shared.mountEFI()
                    } label: {
                        Text("挂载 EFI 分区（用于驱动管理）")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.rogRed.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    Button {
                        if let d = DriverManager.locateOC() {
                            NSWorkspace.shared.selectFile(d + "/config.plist", inFileViewerRootedAtPath: d)
                        }
                    } label: {
                        Text("在访达中打开 config.plist")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.blue.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }

            PanelCard(title: "关于", meta: "1.1.0") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ROG 奥创中心 for macOS · 原生 SwiftUI")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundColor(.white)
                    Text("监控数据全部本地读取，不上传任何信息。驱动中心仅修改本机 EFI 分区的 Kexts 与 config.plist，每次操作前自动备份。")
                        .font(.system(size: 11)).foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - 诊断报告
@MainActor
enum Diagnostics {
    static func build() -> String {
        let m = SystemMonitor.shared
        let dm = DriverManager.shared
        var lines: [String] = []
        lines.append("ROG 奥创中心 · 诊断报告")
        lines.append("时间：\(Date())")
        lines.append("系统：\(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("机型：\(HardwareProbe.run("/usr/sbin/sysctl", ["-n", "hw.model"]).trimmingCharacters(in: .whitespacesAndNewlines))")
        lines.append("内核：\(AdvancedPage.kernelVersion)")
        lines.append("")
        lines.append("== 传感器 ==")
        lines.append("CPU 温度：\(String(format: "%.1f", m.cpuTemp)) °C（\(m.tempSource)）")
        lines.append("风扇：\(m.fanRPM.isEmpty ? "无数据" : m.fanRPM.map { String(format: "%.0f", $0) }.joined(separator: ", ") + " RPM")")
        lines.append("CPU / 内存 / 磁盘：\(String(format: "%.1f", m.cpuUsage))% / \(String(format: "%.1f", m.ramUsage))% / \(String(format: "%.1f", m.diskUsage))%")
        lines.append("")
        lines.append("== EFI 驱动 ==")
        lines.append("挂载点：\(dm.ocPath ?? "未挂载")")
        if dm.kexts.isEmpty { dm.refresh() }
        for k in dm.kexts {
            lines.append("\(k.enabled ? "[启用]" : "[禁用]") \(k.name) \(k.version)  bundle=\(k.bundle) loaded=\(k.loaded)")
        }
        lines.append("")
        lines.append("== 已加载第三方 kext ==")
        let loaded = DriverManager.kextstat().filter { !$0.hasPrefix("com.apple.") }.sorted()
        lines.append(loaded.isEmpty ? "（无）" : loaded.joined(separator: "\n"))
        return lines.joined(separator: "\n")
    }

    static func save(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/ROG诊断-\(f.string(from: Date())).txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
