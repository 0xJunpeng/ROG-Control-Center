import SwiftUI

// MARK: - 主控制台窗口
struct MainConsoleView: View {
    @ObservedObject var m = SystemMonitor.shared
    @State private var page: Int
    @State private var mode = 2
    @State private var ledColor = AppTheme.rogRed
    private let driverHW: HardwareInfo?

    init(initialPage: Int = 0, driverHW: HardwareInfo? = nil) {
        _page = State(initialValue: initialPage)
        self.driverHW = driverHW
    }

    private let navItems: [(String, String)] = [
        ("概览", "square.grid.2x2"),
        ("驱动中心", "shippingbox.fill"),
        ("性能与风扇", "bolt.fill"),
        ("键盘灯效", "keyboard"),
        ("实时监控", "waveform.path.ecg"),
        ("菜单栏", "menubar.rectangle"),
        ("高级", "slider.horizontal.3"),
        ("设置", "gearshape"),
        ("关于", "info.circle"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(minWidth: 980, minHeight: 620)
        .preferredColorScheme(.dark)
        .background(AppTheme.bg)
    }

    // MARK: 侧边栏
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    CutCornerRect(cut: 7)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                    Text("R")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(AppTheme.rogRed)
                        .shadow(color: AppTheme.rogRed.opacity(0.8), radius: 6)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROG 奥创中心")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text("ARMOURY CRATE")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(AppTheme.rogRed)
                        .tracking(2.5)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(navItems.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 10) {
                        Image(systemName: item.1)
                            .font(.system(size: 13))
                            .frame(width: 18)
                        Text(item.0)
                            .font(.system(size: 13, weight: page == i ? .semibold : .regular))
                        Spacer()
                        if i == 0 {
                            Circle().fill(AppTheme.rogRed).frame(width: 5, height: 5)
                                .shadow(color: AppTheme.rogRed, radius: 3)
                        }
                    }
                    .foregroundColor(page == i ? .white : Color.white.opacity(0.5))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(page == i ? AnyShapeStyle(LinearGradient(colors: [AppTheme.rogRed.opacity(0.18), AppTheme.rogRed.opacity(0.04)], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.clear))
                    )
                    .overlay(alignment: .leading) {
                        if page == i {
                            Rectangle().fill(AppTheme.rogRed)
                                .frame(width: 3, height: 18).cornerRadius(2)
                                .shadow(color: AppTheme.rogRed, radius: 3)
                                .padding(.leading, 0)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { page = i }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            HStack(spacing: 7) {
                Circle().fill(AppTheme.green).frame(width: 7, height: 7)
                    .shadow(color: AppTheme.green, radius: 3)
                Text(m.hasSMC ? "SMC 传感器在线" : "SMC 不可用")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            .padding(18)
        }
        .frame(width: 216)
        .background(
            LinearGradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.065), Color(red: 0.038, green: 0.038, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
        }
    }

    // MARK: 内容区
    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch page {
                    case 0: overviewPage
                    case 1: DriverCenterView(presetHW: driverHW)
                    case 2: PerformancePage()
                    case 3: keyboardPage
                    case 4: monitorPage
                    case 5: MenuBarPage()
                    case 6: AdvancedPage()
                    case 7: SettingsPage()
                    case 8: aboutPage
                    default: placeholderPage
                    }
                }
                .padding(24)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 11) {
                    Rectangle()
                        .fill(LinearGradient(colors: [AppTheme.rogRed, AppTheme.rogRed.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 5, height: 24)
                        .shadow(color: AppTheme.rogRed.opacity(0.6), radius: 4)
                    Text(navItems[page].0)
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(.white)
                }
                Text("更新于 \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)) · 每 2 秒刷新")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.leading, 16)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    // MARK: 概览页
    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                statCard(label: "性能模式", value: ["安静", "均衡", "性能"][mode], sub: "灯效 0x\(30 + mode) 红", color: AppTheme.rogRed)
                statCard(label: "CPU 温度",
                         value: m.cpuTemp > 0 ? String(format: "%.0f°C", m.cpuTemp) : "—",
                         sub: "SMC 传感器",
                         color: m.cpuTemp > 80 ? AppTheme.rogRed : AppTheme.orange)
                statCard(label: m.fanRPM.count > 1 ? "双风扇" : "主风扇",
                         value: m.fanRPM.isEmpty ? "—" : String(format: "%.0f", m.fanRPM[0]),
                         sub: "RPM · SMC 读取",
                         color: AppTheme.blue)
            }

            PanelCard(title: "设备", meta: "ProjectID 0x1a") {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("识别").font(.system(size: 11)).foregroundColor(.gray)
                        Text("\(Host.current().localizedName ?? "Mac") · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("CPU \(ProcessInfo.processInfo.processorCount) 核 · \(ProcessInfo.processInfo.physicalMemory / 1073741824) GB")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                }
                HStack(spacing: 8) {
                    badge("SMC 传感器 \(m.hasSMC ? "✓" : "✕")", on: m.hasSMC)
                    badge("风扇 ×\(max(1, m.fanRPM.count)) \(m.fanRPM.isEmpty ? "✕" : "✓")", on: !m.fanRPM.isEmpty)
                    badge("温度读取 \(m.cpuTemp > 0 ? "✓" : "✕")", on: m.cpuTemp > 0)
                }
            }

            PanelCard(title: "性能模式", meta: "演示 · 不写入 EC") {
                HStack(spacing: 12) {
                    modeCard(0, icon: "moon.fill", name: "安静", desc: "静音 · 低功耗")
                    modeCard(1, icon: "circle.lefthalf.filled", name: "均衡", desc: "日常 · 平衡")
                    modeCard(2, icon: "flame.fill", name: "性能", desc: "释放 · 满血性能")
                }
                Text("本版本为只读监控，模式切换不修改硬件状态。")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            PanelCard(title: "风扇", meta: m.fanRPM.isEmpty ? "未检测到" : "\(m.fanRPM.count) 个") {
                if m.fanRPM.isEmpty {
                    Text("未通过 SMC 读取到风扇转速。")
                        .font(.system(size: 12)).foregroundColor(.gray)
                } else {
                    HStack(spacing: 14) {
                        ForEach(Array(m.fanRPM.enumerated()), id: \.offset) { i, rpm in
                            VStack(spacing: 8) {
                                Text(i == 0 ? "CPU" : "GPU")
                                    .font(.system(size: 11)).foregroundColor(.gray)
                                Text(String(format: "%.0f", rpm))
                                    .font(.system(size: 30, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.white)
                                    .shadow(color: .white.opacity(0.15), radius: 8)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.08))
                                        Capsule().fill(LinearGradient(colors: [AppTheme.rogRed.opacity(0.5), AppTheme.rogRed], startPoint: .leading, endPoint: .trailing))
                                            .frame(width: geo.size.width * min(1, rpm / 6000))
                                            .shadow(color: AppTheme.rogRed, radius: 3)
                                    }
                                }
                                .frame(height: 5)
                                Text("RPM")
                                    .font(.system(size: 9)).foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func statCard(label: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundColor(.gray)
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.5), radius: 8)
            Text(sub).font(.system(size: 10)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.panelGradient))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func badge(_ text: String, on: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(on ? AppTheme.green : .gray)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(on ? AppTheme.green.opacity(0.08) : Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? AppTheme.green.opacity(0.35) : Color.white.opacity(0.1), lineWidth: 1))
            )
    }

    private func modeCard(_ idx: Int, icon: String, name: String, desc: String) -> some View {
        let active = mode == idx
        return VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 20))
            Text(name).font(.system(size: 14, weight: .bold))
            Text(desc).font(.system(size: 10)).foregroundColor(.gray)
        }
        .foregroundColor(active ? AppTheme.rogRed : .white.opacity(0.6))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            CutCornerRect(cut: 12)
                .fill(active ? AnyShapeStyle(LinearGradient(colors: [AppTheme.rogRed.opacity(0.16), AppTheme.rogRed.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.white.opacity(0.04)))
                .overlay(CutCornerRect(cut: 12).stroke(active ? AppTheme.rogRed : Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: active ? AppTheme.rogRed.opacity(0.25) : .clear, radius: 10)
        )
        .contentShape(Rectangle())
        .onTapGesture { mode = idx }
    }

    // MARK: 实时监控页
    private var monitorPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                RingView(value: m.cpuTemp / 100, color: m.cpuTemp > 80 ? AppTheme.rogRed : AppTheme.orange,
                         text: m.cpuTemp > 0 ? String(format: "%.0f", m.cpuTemp) : "—", sub: "°C",
                         title: "CPU 温度")
                RingView(value: m.cpuUsage / 100, color: AppTheme.blue,
                         text: String(format: "%.0f", m.cpuUsage), sub: "%",
                         title: "CPU 占用")
                RingView(value: m.ramUsage / 100, color: AppTheme.cyan,
                         text: String(format: "%.0f", m.ramUsage), sub: "%",
                         title: "内存占用")
                RingView(value: m.diskUsage / 100, color: AppTheme.green,
                         text: String(format: "%.0f", m.diskUsage), sub: "%",
                         title: "磁盘占用")
            }
            .frame(maxWidth: .infinity)

            PanelCard(title: "CPU 占用曲线", meta: "实时 · 60 点") {
                Sparkline(data: m.histCPU, color: AppTheme.blue, range: 0...100)
                    .frame(height: 90)
            }

            PanelCard(title: "CPU 温度曲线", meta: m.cpuTemp > 0 ? String(format: "%.1f °C", m.cpuTemp) : "无传感器") {
                Sparkline(data: m.histTemp, color: AppTheme.orange, range: 30...100)
                    .frame(height: 90)
            }

            HStack(spacing: 16) {
                PanelCard(title: "网络 · 上传", meta: SystemMonitor.speedText(m.upSpeed)) {
                    HStack(spacing: 8) {
                        Circle().fill(AppTheme.rogRed).frame(width: 7, height: 7)
                            .shadow(color: AppTheme.rogRed, radius: 3)
                        Text(SystemMonitor.speedText(m.upSpeed))
                            .font(.system(size: 20, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                PanelCard(title: "网络 · 下载", meta: SystemMonitor.speedText(m.downSpeed)) {
                    HStack(spacing: 8) {
                        Circle().fill(AppTheme.blue).frame(width: 7, height: 7)
                            .shadow(color: AppTheme.blue, radius: 3)
                        Text(SystemMonitor.speedText(m.downSpeed))
                            .font(.system(size: 20, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }

    // MARK: 键盘灯效页（演示）
    private var keyboardPage: some View {
        PanelCard(title: "AURA 灯效预览", meta: "演示 · 未连接 EC") {
            let colors: [Color] = [AppTheme.rogRed,
                                   Color(red: 1, green: 0.48, blue: 0),
                                   Color(red: 1, green: 0.83, blue: 0),
                                   AppTheme.green, AppTheme.blue,
                                   Color(red: 0.64, green: 0.30, blue: 1)]
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { r in
                        HStack(spacing: 6) {
                            ForEach(0..<13, id: \.self) { c in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(ledColor)
                                    .frame(width: 30, height: 22)
                                    .shadow(color: ledColor.opacity(0.7), radius: 4)
                                    .opacity(0.55 + 0.45 * Double((r + c) % 3) / 2)
                            }
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.5)))

                HStack(spacing: 12) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                        Circle()
                            .fill(c)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(ledColor == c ? Color.white : .clear, lineWidth: 2))
                            .shadow(color: c.opacity(0.6), radius: 5)
                            .onTapGesture { ledColor = c }
                    }
                    Spacer()
                    Text("点击色块切换键盘灯效颜色")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
        }
    }

    // MARK: 关于页
    private var aboutPage: some View {
        PanelCard(title: "关于", meta: "") {
            VStack(alignment: .leading, spacing: 10) {
                Text("ROG 奥创中心 · for macOS")
                    .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                Text("版本 1.2.0 · 原生 SwiftUI 构建 · DMG 安装")
                    .font(.system(size: 12)).foregroundColor(.gray)
                Text("数据来源：CPU/内存 host_statistics、磁盘 statfs、网络 sysctl(NET_RT_IFLIST2)、温度与风扇 SMC。所有读取均为只读操作，不修改硬件状态。")
                    .font(.system(size: 12)).foregroundColor(.gray)
                    .lineSpacing(4)
            }
        }
    }

    private var placeholderPage: some View {
        PanelCard(title: navItems[page].0, meta: "") {
            Text("该页面将在后续版本中提供。")
                .font(.system(size: 12)).foregroundColor(.gray)
        }
    }
}
