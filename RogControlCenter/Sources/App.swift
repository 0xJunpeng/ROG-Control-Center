import SwiftUI
import AppKit
import ServiceManagement

@main
struct ROGControlCenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // 命令行自检模式：输出一次采样后退出（用于构建验证）
        if CommandLine.arguments.contains("--smc-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                let m = SystemMonitor.shared
                print("RESULT cpu=\(String(format: "%.1f", m.cpuUsage)) ram=\(String(format: "%.1f", m.ramUsage)) disk=\(String(format: "%.1f", m.diskUsage)) temp=\(String(format: "%.1f", m.cpuTemp)) fans=\(m.fanRPM.map { String(format: "%.0f", $0) }.joined(separator: ",")) up=\(String(format: "%.0f", m.upSpeed)) down=\(String(format: "%.0f", m.downSpeed)) smc=\(m.hasSMC)")
                exit(0)
            }
        }

        // 驱动中心自检：打印 EFI 定位与已扫描到的 kext
        if CommandLine.arguments.contains("--drivers-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let dm = DriverManager.shared
                print("EFI_PARTITIONS=\(DriverManager.efiPartitions().joined(separator: ","))")
                dm.refresh()
                print("EFI=\(dm.ocPath ?? "未挂载")")
                print("KEXT_COUNT=\(dm.kexts.count)")
                for k in dm.kexts {
                    print("  \(k.enabled ? "ON " : "OFF") \(k.name) \(k.version) | \(k.bundle) | loaded=\(k.loaded) | inConfig=\(k.inConfig)")
                }
                let loaded = DriverManager.kextstat().filter { !$0.hasPrefix("com.apple.") }.sorted()
                print("LOADED_THIRD_PARTY=\(loaded.count): \(loaded.joined(separator: ","))")
                print("--- 目录匹配 ---")
                for spec in DriverCatalog.all {
                    let st = dm.state(of: spec)
                    if let k = st.installed {
                        print("  ✓ \(spec.name) → \(k.bundle) [\(k.enabled ? "启用" : "禁用")]")
                    }
                }
                let extra = dm.unlisted()
                print("UNLISTED=\(extra.count): \(extra.map(\.displayName).joined(separator: ", "))")
                if let oc = dm.ocPath, let cfg = DriverManager.readPlist(oc + "/config.plist") {
                    let data = (try? PropertyListSerialization.data(fromPropertyList: cfg, format: .xml, options: 0)) ?? Data()
                    let back = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
                    let add = ((back?["Kernel"] as? [String: Any])?["Add"] as? [[String: Any]])?.count ?? -1
                    print("ROUNDTRIP ok=\(back != nil) addCount=\(add) xmlBytes=\(data.count)")
                }
                exit(0)
            }
        }

        // 窗口快照：渲染主窗口内容为 PNG（不依赖屏幕录制权限）
        if let i = CommandLine.arguments.firstIndex(of: "--shot"), CommandLine.arguments.count > i + 1 {
            let path = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                AppSnapshot.shotWindow(to: path)
                exit(0)
            }
        }

        // 页面快照：把指定页面渲染成 PNG（用于版式自检）
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-page"),
           CommandLine.arguments.count > i + 2 {
            let pageIdx = Int(CommandLine.arguments[i + 1]) ?? 0
            let path = CommandLine.arguments[i + 2]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                AppSnapshot.renderPage(pageIdx, to: path)
                exit(0)
            }
        }

        // 设计自检模式：把状态栏小部件渲染成图片（浅色/深色各一份）
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 1 {
            let path = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                AppSnapshot.renderStatusBar(to: path)
                exit(0)
            }
        }
    }

    var body: some Scene {
        // 主窗口与菜单栏状态项均由 AppDelegate 以 AppKit 方式管理
        // （SwiftUI 的 MenuBarExtra 无法保留自定义视图的颜色与完整布局）
        Settings {
            EmptyView()
        }
    }
}

// MARK: - 全局跳转
enum AppRouter {
    static func showConsole() {
        (NSApp.delegate as? AppDelegate)?.showConsole()
    }
}

// MARK: - 设计自检：把状态栏小部件渲染为 PNG
@MainActor
enum AppSnapshot {
    static func renderStatusBar(to path: String) {
        let dark = StatusBarView()
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color(red: 0.13, green: 0.13, blue: 0.14))
            .environment(\.colorScheme, .dark)
        let light = StatusBarView()
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color(white: 0.95))
            .environment(\.colorScheme, .light)
        let card = VStack(spacing: 8) { dark; light }
            .padding(10)
            .background(Color(white: 0.55))

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("SNAPSHOT failed")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("SNAPSHOT ok -> \(path) size=\(rep.pixelsWide)x\(rep.pixelsHigh)")
    }

    static func renderPage(_ page: Int, to path: String) {
        DriverManager.shared.refresh()
        let hw = HardwareProbe.probe()
        let view = MainConsoleView(initialPage: page, driverHW: hw)
            .frame(width: 1240, height: 940)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("PAGE_SNAPSHOT failed")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("PAGE_SNAPSHOT ok -> \(path) size=\(rep.pixelsWide)x\(rep.pixelsHigh)")
    }

    /// 离屏渲染主窗口内容（--page N --shot path）
    static func shotWindow(to path: String) {
        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = w.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("SHOT fail")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("SHOT fail encode")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("SHOT ok -> \(path) size=\(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
}

// MARK: - 启动参数
enum AppLaunch {
    static let args = CommandLine.arguments
    /// 以指定页码打开主窗口（--page N，用于测试）
    static var startPage: Int {
        if let i = args.firstIndex(of: "--page"), args.count > i + 1, let n = Int(args[i + 1]) { return n }
        return 0
    }
    static var windowOnly: Bool { args.contains("--page") }
}

// MARK: - AppDelegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // 后台常驻，无 Dock 图标
        if !AppLaunch.windowOnly { StatusItemController.shared.install() }
        showConsole()
    }

    func showConsole() {
        if window == nil { window = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "ROG 奥创中心"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.backgroundColor = NSColor(AppTheme.bg)
        w.isMovableByWindowBackground = true
        w.minSize = NSSize(width: 980, height: 620)

        // 先给定尺寸再设为 contentView，否则窗口会被压成 0
        let host = NSHostingView(rootView: MainConsoleView(initialPage: AppLaunch.startPage))
        host.frame = NSRect(x: 0, y: 0, width: 1180, height: 760)
        w.contentView = host
        w.setContentSize(NSSize(width: 1180, height: 760))

        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("ROGMainConsoleWindow")
        if !w.setFrameUsingName("ROGMainConsoleWindow") { w.center() }
        return w
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // 关闭窗口后继续在菜单栏后台运行
    }
}
