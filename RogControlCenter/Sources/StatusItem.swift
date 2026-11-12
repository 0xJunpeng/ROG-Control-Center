import AppKit
import SwiftUI

// MARK: - 点击穿透的宿主视图（让状态栏按钮收到鼠标事件）
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - 状态栏控制器：NSStatusItem + 自定义彩色视图 + NSPopover 面板
//
// 说明：SwiftUI 的 MenuBarExtra(label:) 会把自定义视图渲染成「模板图片」，
// 颜色会被抹掉、复杂布局会被裁切（表现为只剩第一段文字）。
// 因此这里直接用 AppKit 的 NSStatusItem 承载 NSHostingView，保留完整颜色与布局。
final class StatusItemController: NSObject, NSPopoverDelegate {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var hostingView: NSView?
    private let popover = NSPopover()

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
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "ROG 奥创中心 · 左键打开控制台 / 右键快捷面板"
        button.setAccessibilityLabel("ROG 奥创中心")

        // 宿主视图铺满按钮，内容在内部居中（避免 menus bar 尚未布局导致 frame 计算出负数而不可见）
        let host = PassthroughHostingView(
            rootView: StatusBarView().frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        host.autoresizingMask = [.width, .height]
        host.frame = button.bounds
        button.addSubview(host)

        statusItem = item
        hostingView = host

        // 弹出面板
        let panel = NSHostingController(rootView: MenuPanelView())
        panel.sizingOptions = [.preferredContentSize]
        popover.contentViewController = panel
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        // 显示项变化时重新计算状态项宽度
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(defaultsChanged),
                                              name: UserDefaults.didChangeNotification,
                                              object: nil)
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

    // MARK: 交互
    //
    // 左键直接打开控制台窗口（用户的核心诉求），右键弹出快捷面板。
    // 之前「点击没反应」的根因是 accessory 应用激活失败 —— 现在直接走
    // showConsole()（内部切 .regular 激活策略），不再依赖 popover 路径。
    @objc private func handleClick() {
        let t = NSApp.currentEvent?.type.rawValue ?? 0
        NSLog("ROG: statusClick type=%d", t)
        (NSApp.delegate as? AppDelegate)?.diagLog("statusClick event=\(t)")
        if let e = NSApp.currentEvent, e.type == .rightMouseUp {
            if popover.isShown { closePopover() } else { showPopover() }
        } else {
            closePopover()
            AppRouter.showConsole()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }
}
