import SwiftUI
import AppKit

// MARK: - 驱动中心
struct DriverCenterView: View {
    @ObservedObject private var dm = DriverManager.shared

    @State private var hw: HardwareInfo?
    @State private var filter: DriverCategory?
    @State private var onlyInstalled = false
    @State private var working: String?
    @State private var showLog = false
    @State private var search = ""

    init(presetHW: HardwareInfo? = nil) {
        _hw = State(initialValue: presetHW)
    }

    private var specs: [DriverSpec] {
        var list = DriverCatalog.all
        if let f = filter { list = list.filter { $0.category == f } }
        if !search.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(search)
                || $0.summary.localizedCaseInsensitiveContains(search)
                || $0.category.rawValue.contains(search)
            }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hardwareBar
            efiBar
            filterBar
            if onlyInstalled {
                installedSection
            } else {
                driverList
            }
            footerBar
            if showLog { logPanel }
        }
        .task {
            if dm.kexts.isEmpty { dm.refresh() }   // 先扫驱动（快）
            if hw == nil {
                hw = await Task.detached(priority: .userInitiated) { HardwareProbe.probe() }.value
            }
        }
    }

    // MARK: 硬件概览
    private var hardwareBar: some View {
        HStack(spacing: 10) {
            hwChip(icon: "cpu", title: "平台", value: hw?.cpu ?? "检测中…", tint: AppTheme.rogRed)
            hwChip(icon: "speaker.wave.2.fill", title: "声卡", value: hw?.audio ?? "…",
                   tint: (hw?.audio ?? "").contains("Realtek") ? AppTheme.green : AppTheme.orange)
            hwChip(icon: "cable.connector", title: "有线网卡", value: hw?.ethernet ?? "…",
                   tint: (hw?.ethernet ?? "").contains("未检测") ? .gray : AppTheme.green)
            hwChip(icon: "wifi", title: "无线", value: hw?.wifi ?? "…",
                   tint: (hw?.wifi ?? "").contains("未检测") ? .gray : AppTheme.blue)
            hwChip(icon: "display", title: "显卡", value: hw?.gpu ?? "…", tint: AppTheme.cyan)
        }
    }

    private func hwChip(icon: String, title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(title).font(.system(size: 10))
            }
            .foregroundColor(tint)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.2), lineWidth: 1))
    }

    // MARK: EFI 状态
    private var efiBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(dm.isEFIMounted ? AppTheme.green : AppTheme.orange)
                    .frame(width: 8, height: 8)
                    .shadow(color: (dm.isEFIMounted ? AppTheme.green : AppTheme.orange).opacity(0.8), radius: 4)
                Text(dm.isEFIMounted ? "EFI 已挂载" : "EFI 未挂载")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                if let v = dm.efiVolume {
                    Text(v).font(.system(size: 11, design: .monospaced)).foregroundColor(.gray)
                }
            }
            Spacer()
            if dm.needsRestart {
                Text("· 有改动待重启生效 ·")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.orange)
            }
            Text(dm.statusText).font(.system(size: 11)).foregroundColor(.gray)
            Button {
                if dm.isEFIMounted { dm.refresh() } else { dm.mountEFI() }
            } label: {
                Text(dm.isEFIMounted ? "重新扫描" : "挂载 EFI")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.rogRed.opacity(0.75)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }

    // MARK: 分类筛选
    private var filterBar: some View {
        HStack(spacing: 8) {
            chip("已安装 \(dm.kexts.filter { !$0.isPlugin }.count)", icon: "checkmark.seal",
                 active: onlyInstalled) {
                onlyInstalled = true
                filter = nil
            }
            chip("全部", active: !onlyInstalled && filter == nil) { filter = nil; onlyInstalled = false }
            ForEach(DriverCategory.allCases) { c in
                chip(c.rawValue, icon: c.icon, active: filter == c) { filter = c; onlyInstalled = false }
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundColor(.gray)
                TextField("搜索驱动", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 110)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
        }
    }

    private func chip(_ title: String, icon: String? = nil, active: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            if let i = icon { Image(systemName: i).font(.system(size: 9)) }
            Text(title).font(.system(size: 11, weight: active ? .bold : .regular))
        }
        .foregroundColor(active ? .white : .gray)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(
            CutCornerRect(cut: 5)
                .fill(active ? AnyShapeStyle(LinearGradient(colors: [AppTheme.rogRed.opacity(0.8), AppTheme.rogRed.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.white.opacity(0.05)))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    // MARK: 驱动列表
    private var driverList: some View {
        VStack(spacing: 8) {
            if specs.isEmpty {
                Text("没有匹配的驱动").font(.system(size: 12)).foregroundColor(.gray).padding(.vertical, 30)
            }
            ForEach(specs) { spec in
                driverRow(spec)
            }
        }
    }

    private func driverRow(_ spec: DriverSpec) -> some View {
        let st = dm.state(of: spec)
        let installed = st.installed
        let isWorking = working == spec.name

        return HStack(alignment: .top, spacing: 12) {
            // 分类图标
            ZStack {
                CutCornerRect(cut: 6)
                    .fill(spec.category == .core ? AppTheme.rogRed.opacity(0.16) : Color.white.opacity(0.05))
                    .frame(width: 36, height: 36)
                Image(systemName: spec.category.icon)
                    .font(.system(size: 14))
                    .foregroundColor(spec.category == .core ? AppTheme.rogRed : .white.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(spec.name)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.white)
                    if let v = installed?.version, v != "—" {
                        Text("v\(v)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    if spec.required {
                        Text("基础")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppTheme.rogRed)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).fill(AppTheme.rogRed.opacity(0.14)))
                    }
                    statusBadge(installed)
                    if let k = installed, !dm.plugins(of: k.bundlePath).isEmpty {
                        badge("\(dm.plugins(of: k.bundlePath).count) 插件", AppTheme.cyan)
                    }
                    Spacer()
                }
                Text(spec.summary)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if installed != nil {
                    Text(spec.note)
                        .font(.system(size: 10.5))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 操作区
            HStack(spacing: 6) {
                if isWorking {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else if let k = installed {
                    smallButton(k.enabled ? "禁用" : "启用", k.enabled ? AppTheme.orange : AppTheme.green) {
                        do { try dm.setEnabled(bundlePath: k.bundlePath, enabled: !k.enabled) }
                        catch { alert("操作失败", error.localizedDescription) }
                    }
                    smallButton("卸载", .gray) {
                        guard confirm("卸载 \(spec.name)？",
                                      "将从 EFI/OC/Kexts 移除该 kext 并删除 config.plist 中的对应条目。\n原文件会备份到 Kexts-Removed，可手动找回。") else { return }
                        do { try dm.remove(bundlePath: k.bundlePath) }
                        catch { alert("卸载失败", error.localizedDescription) }
                    }
                } else if spec.bundled {
                    smallButton("安装", AppTheme.rogRed, filled: true) { install(spec) }
                } else if spec.autoDownloadable {
                    smallButton("安装", AppTheme.rogRed, filled: true) { install(spec) }
                } else {
                    if spec.homepage != nil {
                        smallButton("下载页", AppTheme.blue) { open(spec.homepage) }
                    }
                    smallButton("导入", AppTheme.rogRed, filled: true) { importKext() }
                }
            }
            .frame(width: 132, alignment: .trailing)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(installed != nil ? Color.white.opacity(0.055) : Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(installed?.enabled == true ? AppTheme.green.opacity(0.22) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func statusBadge(_ k: InstalledKext?) -> some View {
        Group {
            if let k = k {
                if !k.inConfig || !FileManager.default.fileExists(atPath: k.path) {
                    badge("文件缺失", AppTheme.rogRed)
                } else if k.enabled {
                    badge("已启用", AppTheme.green)
                } else {
                    badge("已禁用", AppTheme.orange)
                }
                if k.loaded { badge("运行中", AppTheme.blue) }
            } else {
                badge("未安装", .gray)
            }
        }
    }

    // MARK: 已安装视图（EFI 中全部驱动，含目录未收录的）
    private var installedSection: some View {
        let items = dm.kexts.filter { !$0.isPlugin }
        let plugins = dm.kexts.filter { $0.isPlugin }
        return VStack(spacing: 8) {
            if !dm.isEFIMounted {
                hintCard("EFI 未挂载", "点上方「挂载 EFI」后，这里会列出 OC/Kexts 中的全部驱动，可直接启用、禁用或卸载。")
            } else if items.isEmpty {
                hintCard("EFI 中没有驱动", "OC/Kexts 目录为空，或 config.plist 尚未登记任何 kext。")
            }
            ForEach(items) { installedRow($0) }
            if !plugins.isEmpty {
                Text("另有 \(plugins.count) 个内嵌插件（位于父驱动 Contents/PlugIns 下），随父驱动一起加载，未单独列出。")
                    .font(.system(size: 10.5))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    private func installedRow(_ k: InstalledKext) -> some View {
        let spec = dm.spec(for: k)
        let pluginCount = dm.plugins(of: k.bundlePath).count
        let isWorking = working == k.bundlePath

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                CutCornerRect(cut: 6)
                    .fill(k.loaded ? AppTheme.green.opacity(0.14) : Color.white.opacity(0.05))
                    .frame(width: 36, height: 36)
                Image(systemName: spec?.category.icon ?? "puzzlepiece.extension")
                    .font(.system(size: 14))
                    .foregroundColor(k.loaded ? AppTheme.green : .white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(k.displayName)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.white)
                    if k.version != "—" {
                        Text("v\(k.version)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    statusBadge(k)
                    if pluginCount > 0 { badge("\(pluginCount) 插件", AppTheme.cyan) }
                    Spacer()
                }
                Text(k.bundle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                if let s = spec {
                    Text(s.summary)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if isWorking {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    smallButton(k.enabled ? "禁用" : "启用", k.enabled ? AppTheme.orange : AppTheme.green) {
                        do { try dm.setEnabled(bundlePath: k.bundlePath, enabled: !k.enabled) }
                        catch { alert("操作失败", error.localizedDescription) }
                    }
                    smallButton("卸载", .gray) {
                        guard confirm("卸载 \(k.displayName)？",
                                      "将从 EFI/OC/Kexts 移除，并删除 config.plist 中的对应条目。\n原文件会备份到 Kexts-Removed。") else { return }
                        do { try dm.remove(bundlePath: k.bundlePath) }
                        catch { alert("卸载失败", error.localizedDescription) }
                    }
                }
            }
            .frame(width: 132, alignment: .trailing)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(k.enabled ? 0.055 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(k.enabled ? AppTheme.green.opacity(0.2) : Color.white.opacity(0.06), lineWidth: 1))
    }

    private func hintCard(_ title: String, _ msg: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").foregroundColor(AppTheme.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Text(msg).font(.system(size: 11)).foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.orange.opacity(0.07)))
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.3), lineWidth: 0.6))
    }

    private func smallButton(_ title: String, _ color: Color, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(filled ? .white : color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(filled ? color.opacity(0.8) : color.opacity(0.12))
                )
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(filled ? 0 : 0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: 底部工具条
    private var footerBar: some View {
        HStack(spacing: 10) {
            smallButton("从文件安装 kext", AppTheme.rogRed, filled: true) { importKext() }
            smallButton("备份 config.plist", AppTheme.blue) {
                do { try dm.backup(reason: "manual") } catch { alert("备份失败", error.localizedDescription) }
            }
            smallButton("恢复最近备份", AppTheme.orange) { restoreLatest() }
            smallButton(showLog ? "隐藏日志" : "操作日志", .gray) { showLog.toggle() }
            Spacer()
            Text("改动写入 EFI，重启后生效")
                .font(.system(size: 10.5))
                .foregroundColor(.gray)
        }
    }

    private var logPanel: some View {
        PanelCard(title: "操作日志", meta: "\(dm.log.count) 条") {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if dm.log.isEmpty {
                        Text("暂无记录").font(.system(size: 11)).foregroundColor(.gray)
                    }
                    ForEach(Array(dm.log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 110)
        }
    }

    // MARK: 操作
    private func install(_ spec: DriverSpec) {
        if spec.bundled {
            guard confirm("安装 \(spec.name)？",
                          "该驱动随 App 内置，无需联网。\n将写入 EFI/OC/Kexts 并登记到 config.plist，安装前自动备份配置，重启后生效。") else { return }
            working = spec.name
            Task { @MainActor in
                defer { working = nil }
                do { try dm.installBundled(spec: spec); dm.statusText = "已安装 \(spec.name) · 重启后生效" }
                catch { alert("安装失败", error.localizedDescription) }
            }
            return
        }
        guard confirm("安装 \(spec.name)？",
                      "会从 GitHub 下载最新正式版并写入 EFI/OC/Kexts，同时登记到 config.plist。\n安装前会自动备份 config.plist，改动需重启后生效。") else { return }
        working = spec.name
        Task { @MainActor in
            defer { working = nil }
            do { try await dm.downloadAndInstall(spec: spec) }
            catch { alert("安装失败", error.localizedDescription) }
        }
    }

    private func importKext() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "安装"
        panel.message = "选择 .kext 或包含 kext 的 .zip 压缩包"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var kextURL = url
            if url.pathExtension.lowercased() == "zip" {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("rog-import-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                try DriverManager.unzip(url, to: tmp)
                guard let found = DriverManager.findKext(in: tmp, named: "") else {
                    throw DriverManager.DriverError.message("压缩包里没找到 .kext")
                }
                kextURL = found
            }
            guard kextURL.pathExtension == "kext" else {
                throw DriverManager.DriverError.message("请选择 .kext 目录或 .zip 压缩包")
            }
            guard confirm("安装 \(kextURL.lastPathComponent)？",
                          "将写入 EFI/OC/Kexts 并登记到 config.plist，重启后生效。") else { return }
            try dm.install(kextURL: kextURL)
        } catch {
            alert("导入失败", error.localizedDescription)
        }
    }

    private func restoreLatest() {
        let list = dm.backupList()
        guard let latest = list.first else {
            alert("没有备份", "当前 EFI 里没有找到配置备份。")
            return
        }
        guard confirm("恢复配置备份？", "将用 \(latest) 覆盖 config.plist，当前配置会先自动备份一次。") else { return }
        do {
            try dm.backup(reason: "before-restore")
            try dm.restoreBackup(named: latest)
        } catch {
            alert("恢复失败", error.localizedDescription)
        }
    }

    private func open(_ urlString: String?) {
        guard let s = urlString, let u = URL(string: s) else { return }
        NSWorkspace.shared.open(u)
    }

    private func confirm(_ title: String, _ msg: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = msg
        a.alertStyle = .warning
        a.addButton(withTitle: "继续")
        a.addButton(withTitle: "取消")
        return a.runModal() == .alertFirstButtonReturn
    }

    private func alert(_ title: String, _ msg: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = msg
        a.alertStyle = .informational
        a.addButton(withTitle: "好")
        a.runModal()
    }
}
