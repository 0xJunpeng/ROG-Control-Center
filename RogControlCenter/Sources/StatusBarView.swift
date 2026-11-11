import SwiftUI
import AppKit
import ServiceManagement

// MARK: - 菜单栏状态小部件（方案 C · 彩色毛玻璃，自适应深浅色菜单栏）
struct StatusBarView: View {
    @ObservedObject var m = SystemMonitor.shared
    @AppStorage("mb.showCPU") private var showCPU = true
    @AppStorage("mb.showRAM") private var showRAM = true
    @AppStorage("mb.showSSD") private var showSSD = true
    @AppStorage("mb.showNet") private var showNet = true

    // 菜单栏在浅色/深色外观下都会正确解析
    private var ink: Color { Color(nsColor: .labelColor) }
    private var dim: Color { Color(nsColor: .secondaryLabelColor) }
    private var pillFill: Color { Color.primary.opacity(0.10) }

    private var cpuTint: Color {
        if m.cpuUsage >= 85 { return AppTheme.rogRed }
        if m.cpuUsage >= 60 { return AppTheme.orange }
        return AppTheme.green
    }

    var body: some View {
        HStack(spacing: 2.5) {
            if showCPU { metric("CPU", m.cpuUsage, tint: cpuTint) }
            if showRAM { metric("RAM", m.ramUsage, tint: AppTheme.blue) }
            if showSSD { metric("SSD", m.diskUsage, tint: AppTheme.cyan) }
            if showNet { net }
        }
        .padding(.horizontal, 3)
        .fixedSize()
    }

    // MARK: 单个指标胶囊
    private func metric(_ key: String, _ value: Double, tint: Color) -> some View {
        HStack(spacing: 2) {
            Text(key)
                .font(.system(size: 7.5, weight: .heavy))
                .tracking(0.2)
                .foregroundColor(tint)
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(ink)
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2.5)
        .background(SlantRect(slant: 2).fill(pillFill))
    }

    // MARK: 网速区（↑ 红 / ↓ 蓝）
    private var net: some View {
        HStack(spacing: 4) {
            HStack(spacing: 1) {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 5.5, weight: .bold))
                    .foregroundColor(AppTheme.rogRed)
                Text(SystemMonitor.compactSpeed(m.upSpeed))
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(dim)
                    .frame(width: 25, alignment: .leading)
            }
            HStack(spacing: 1) {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 5.5, weight: .bold))
                    .foregroundColor(AppTheme.blue)
                Text(SystemMonitor.compactSpeed(m.downSpeed))
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(dim)
                    .frame(width: 25, alignment: .leading)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2.5)
        .background(SlantRect(slant: 2).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - 状态栏点击弹出的面板
struct MenuPanelView: View {
    @ObservedObject var m = SystemMonitor.shared
    @State private var launchAtLogin = SMAppServiceCheck.isEnabled

    var body: some View {
        VStack(spacing: 16) {
            // 顶部标题
            HStack(spacing: 10) {
                ZStack {
                    CutCornerRect(cut: 5)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 34, height: 34)
                    Text("R")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(AppTheme.rogRed)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROG 奥创中心")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text("监控运行中 · 每 2 秒刷新")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                Spacer()
            }

            Divider().overlay(Color.white.opacity(0.08))

            // 概览数据
            VStack(spacing: 10) {
                row("CPU 占用", String(format: "%.0f%%", m.cpuUsage), AppTheme.rogRed)
                row("内存占用", String(format: "%.0f%%", m.ramUsage), AppTheme.blue)
                row("磁盘占用", String(format: "%.0f%%", m.diskUsage), AppTheme.cyan)
                row("上传速度", SystemMonitor.speedText(m.upSpeed), AppTheme.orange)
                row("下载速度", SystemMonitor.speedText(m.downSpeed), AppTheme.green)
                row("CPU 温度", m.cpuTemp > 0 ? String(format: "%.0f °C", m.cpuTemp) : "不可用", m.cpuTemp > 80 ? AppTheme.rogRed : AppTheme.green)
                if !m.fanRPM.isEmpty {
                    ForEach(Array(m.fanRPM.enumerated()), id: \.offset) { i, rpm in
                        row(i == 0 ? "CPU 风扇" : "风扇 \(i + 1)", String(format: "%.0f RPM", rpm), AppTheme.blue)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))

            Divider().overlay(Color.white.opacity(0.08))

            // 功能按钮
            Button {
                StatusItemController.shared.closePopover()
                AppRouter.showConsole()
            } label: {
                HStack {
                    Image(systemName: "gamecontroller.fill")
                    Text("打开控制台")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [AppTheme.rogRed.opacity(0.85), AppTheme.rogRed.opacity(0.55)],
                                             startPoint: .leading, endPoint: .trailing))
                )
            }
            .buttonStyle(.plain)

            Toggle(isOn: $launchAtLogin) {
                HStack {
                    Image(systemName: "power")
                    Text("开机自启动")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: launchAtLogin) { _, newValue in
                SMAppServiceCheck.setEnabled(newValue)
            }

            Divider().overlay(Color.white.opacity(0.08))

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("退出")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(width: 300)
        .preferredColorScheme(.dark)
    }

    private func row(_ key: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 12.5))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

// MARK: - 开机自启动（SMAppService）
enum SMAppServiceCheck {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    static func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("ROGControlCenter: 设置自启动失败 \(error.localizedDescription)")
        }
    }
}
