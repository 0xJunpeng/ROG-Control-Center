import AppKit
import SwiftUI

// MARK: - 点击穿透的宿主视图（让状态栏按钮收到鼠标事件）
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - 状态栏控制器：NSStatusItem + 自定义彩色视图 + 系统菜单
//
// 说明：SwiftUI 的 MenuBarExtra(label:) 会把自定义视图渲染成「模板图片」，
// 颜色会被抹掉、复杂布局会被裁切（表现为只剩第一段文字）。
// 因此这里直接用 AppKit 的 NSStatusItem 承载 NSHostingView，保留完整颜色与布局。
//
// 重要（macOS 26 Tahoe）：第三方状态项的点击被系统交给「控制中心」进程托管
// （CGWindowList 显示状态项窗口 owner=控制中心），按钮的 target/action 直连
// 通道会被架空 —— 表现为「点击没反应」。解决：给 NSStatusItem 挂 NSMenu，
// 菜单由系统菜单机制处理，在托管模式下依然 100% 可靠。
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var hostingView: NSView?
    private let menu = NSMenu()

    private override init() { super.init() }

    func install() {
        guard statusItem == nil else { return }

        // 先用独立实例量出内容自然宽度（决定状态项宽度）
        let probe = NSHostingView(rootView: StatusBarView())
        var measured = probe.fittingSize
        if measured.width < 60 || measured.width > 600 { measured = NSSize(width: 228, height: 22) }
        let length = ceil(measured.width) + 2

        let item = NSStatusBar.system.statusItem(withLength: length)
        guard let button = item.button else { return }

        button.title = ""
        button.image = nil
        button.toolTip = "ROG 奥创中心 · 点击打开菜单"
        button.setAccessibilityLabel("ROG 奥创中心")

        // 宿主视图铺满按钮，内容在内部居中（避免菜单栏尚未布局导致 frame 计算出负数而不可见）
        let host = PassthroughHostingView(
            rootView: StatusBarView().frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        host.autoresizingMask = [.width, .height]
        host.frame = button.bounds
        button.addSubview(host)

        statusItem = item
        hostingView = host

        // 关键：挂系统菜单（macOS 26 控制中心托管点击后唯一可靠入口）
        menu.delegate = self
        rebuildMenuItems()
        item.menu = menu

        // 显示项变化时重新计算状态项宽度
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(defaultsChanged),
                                              name: UserDefaults.didChangeNotification,
                                              object: nil)
    }

    // MARK: 菜单
    private func rebuildMenuItems() {
        menu.removeAllItems()

        let open = NSMenuItem(title: "打开控制台", action: #selector(menuOpenConsole), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        let login = NSMenuItem(title: "开机自启动", action: #selector(menuToggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppServiceCheck.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 ROG 奥创中心", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // 菜单即将显示时刷新状态
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let login = menu.items.first(where: { $0.action == #selector(menuToggleLogin) }) {
            login.state = SMAppServiceCheck.isEnabled ? .on : .off
        }
    }

    @objc private func menuOpenConsole() {
        (NSApp.delegate as? AppDelegate)?.diagLog("menuOpenConsole")
        AppRouter.showConsole()
    }

    @objc private func menuToggleLogin() {
        let target = !SMAppServiceCheck.isEnabled
        SMAppServiceCheck.setEnabled(target)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    @objc private func defaultsChanged() {
        DispatchQueue.main.async { [weak self] in self?.resize() }
    }

    /// 按当前显示项重新量宽
    private func resize() {
        let probe = NSHostingView(rootView: StatusBarView())
        var measured = probe.fittingSize
        if measured.width < 40 || measured.width > 600 { measured = NSSize(width: 228, height: 22) }
        let len = ceil(measured.width) + 2
        if abs((statusItem?.length ?? 0) - len) > 0.5 {
            statusItem?.length = len
        }
    }
}
