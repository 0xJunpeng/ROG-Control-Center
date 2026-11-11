import Foundation
import AppKit

// MARK: - 已安装驱动条目
struct InstalledKext: Identifiable, Hashable {
    let bundle: String
    let name: String
    let version: String
    let bundlePath: String      // 相对路径，如 "AppleALC.kext"
    let path: String            // 绝对路径
    var enabled: Bool           // config.plist 中的 Enabled
    var inConfig: Bool          // 是否登记在 Kernel/Add
    var loaded: Bool            // 当前是否已被内核加载

    var id: String { bundlePath }

    /// 是否为父 kext 内嵌的插件（config 里单独登记，但 UI 应折叠）
    var isPlugin: Bool { bundlePath.contains("/Contents/PlugIns/") }

    /// 内嵌插件所属的父 kext 路径
    var parentBundlePath: String? {
        guard let r = bundlePath.range(of: "/Contents/PlugIns/") else { return nil }
        return String(bundlePath[bundlePath.startIndex..<r.lowerBound])
    }

    /// 去掉插件的冗长前缀，用于显示
    var displayName: String {
        if isPlugin {
            return bundlePath.components(separatedBy: "/").last?.replacingOccurrences(of: ".kext", with: "") ?? name
        }
        return name
    }
}

// MARK: - 驱动管理器
//
// 负责 OpenCore EFI 里 kext 的真实读写：
//   扫描 / 安装 / 启用禁用 / 卸载 / 备份。
// 所有需要 root 的动作都通过 osascript 请求系统授权，
// 普通读写（挂载后的 EFI 目录）直接走 FileManager。
@MainActor
final class DriverManager: ObservableObject {
    static let shared = DriverManager()

    @Published var kexts: [InstalledKext] = []
    @Published var ocPath: String?          // /Volumes/XXX/EFI/OC
    @Published var efiVolume: String?       // /Volumes/XXX
    @Published var busy = false
    @Published var statusText = ""
    @Published var log: [String] = []
    @Published var needsRestart = false

    private init() {}

    // MARK: - 状态

    var isEFIMounted: Bool { ocPath != nil }
    var loadedBundles: Set<String> = []

    func appendLog(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        log.append("[\(f.string(from: Date()))] \(s)")
        if log.count > 120 { log.removeFirst(log.count - 120) }
    }

    // MARK: - 扫描
    func refresh() {
        statusText = "扫描中…"
        loadedBundles = Self.kextstat()

        guard let oc = Self.locateOC() else {
            ocPath = nil
            efiVolume = nil
            kexts = []
            statusText = "EFI 未挂载"
            return
        }
        ocPath = oc
        efiVolume = (oc as NSString).deletingLastPathComponent.replacingOccurrences(of: "/EFI/OC", with: "")

        let fm = FileManager.default
        let kextDir = oc + "/Kexts"
        var entries: [String: (enabled: Bool, exec: String, minK: String, maxK: String)] = [:]
        var order: [String] = []

        // config.plist 中登记的条目（顺序即加载顺序）
        if let cfg = Self.readPlist(oc + "/config.plist"),
           let kernel = cfg["Kernel"] as? [String: Any],
           let add = kernel["Add"] as? [[String: Any]] {
            for item in add {
                guard let bundlePath = item["BundlePath"] as? String else { continue }
                let enabled = (item["Enabled"] as? Bool) ?? (item["Enabled"] as? NSNumber)?.boolValue ?? false
                entries[bundlePath] = (enabled,
                                       item["ExecutablePath"] as? String ?? "",
                                       item["MinKernel"] as? String ?? "",
                                       item["MaxKernel"] as? String ?? "")
                order.append(bundlePath)
            }
        }

        var result: [InstalledKext] = []

        // 磁盘上实际存在的 kext
        let onDisk = (try? fm.contentsOfDirectory(atPath: kextDir))?
            .filter { $0.hasSuffix(".kext") }
            .sorted() ?? []

        for dir in onDisk {
            let full = kextDir + "/" + dir
            let info = full + "/Contents/Info.plist"
            guard let plist = Self.readPlist(info) else { continue }
            let bundle = plist["CFBundleIdentifier"] as? String ?? dir
            let name = (plist["CFBundleName"] as? String)
                ?? dir.replacingOccurrences(of: ".kext", with: "")
            let ver = (plist["CFBundleShortVersionString"] as? String)
                ?? (plist["CFBundleVersion"] as? String) ?? "—"
            let e = entries[dir]
            result.append(InstalledKext(bundle: bundle,
                                        name: name,
                                        version: ver,
                                        bundlePath: dir,
                                        path: full,
                                        enabled: e?.enabled ?? false,
                                        inConfig: e != nil,
                                        loaded: loadedBundles.contains(bundle)))
        }

        // config 里登记但磁盘已缺失的（标记出来，避免用户以为装好了）
        for bp in order where !onDisk.contains(bp) {
            result.append(InstalledKext(bundle: bp,
                                        name: bp.replacingOccurrences(of: ".kext", with: ""),
                                        version: "—",
                                        bundlePath: bp,
                                        path: kextDir + "/" + bp,
                                        enabled: entries[bp]?.enabled ?? false,
                                        inConfig: true,
                                        loaded: false))
        }

        // 按 config 顺序排序，未登记的排后面
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        result.sort { a, b in
            let ra = rank[a.bundlePath] ?? 999
            let rb = rank[b.bundlePath] ?? 999
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        kexts = result
        statusText = "\(result.count) 个驱动 · EFI 已挂载"
    }

    func state(of spec: DriverSpec) -> (installed: InstalledKext?, matches: [InstalledKext]) {
        let hit = kexts.filter { !$0.isPlugin && spec.matches(bundle: $0.bundle, displayName: $0.displayName, bundlePath: $0.bundlePath) }
        return (hit.first, hit)
    }

    /// 目录中未收录、但 EFI 里实际存在的驱动
    func unlisted() -> [InstalledKext] {
        kexts.filter { k in
            guard !k.isPlugin else { return false }
            return !DriverCatalog.all.contains {
                $0.matches(bundle: k.bundle, displayName: k.displayName, bundlePath: k.bundlePath)
            }
        }
    }

    /// 某个父 kext 下的内嵌插件
    func plugins(of parent: String) -> [InstalledKext] {
        kexts.filter { $0.isPlugin && $0.parentBundlePath == parent }
    }

    /// 已安装条目对应的目录定义（用于取分类与说明）
    func spec(for k: InstalledKext) -> DriverSpec? {
        DriverCatalog.all.first {
            $0.matches(bundle: k.bundle, displayName: k.displayName, bundlePath: k.bundlePath)
        }
    }

    // MARK: - EFI 定位与挂载
    static func locateOC() -> String? {
        let fm = FileManager.default
        guard let vols = try? fm.contentsOfDirectory(atPath: "/Volumes") else { return nil }
        // 优先已挂载且带 OC 的卷
        for v in vols.sorted() {
            let oc = "/Volumes/\(v)/EFI/OC"
            if fm.fileExists(atPath: oc + "/config.plist") { return oc }
        }
        return nil
    }

    /// EFI 分区设备列表（diskXsY）
    static func efiPartitions() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = ["list", "-plist"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let disks = plist["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }
        var out: [String] = []
        for d in disks {
            guard let parts = d["Partitions"] as? [[String: Any]] else { continue }
            for part in parts {
                let content = (part["Content"] as? String) ?? ""
                if content.uppercased() == "EFI", let id = part["DeviceIdentifier"] as? String {
                    out.append(id)
                }
            }
        }
        return out
    }

    /// 挂载 EFI（需要管理员授权），成功后刷新状态
    @discardableResult
    func mountEFI() -> Bool {
        if Self.locateOC() != nil { refresh(); return true }
        let parts = Self.efiPartitions()
        guard !parts.isEmpty else {
            appendLog("未找到 EFI 分区")
            statusText = "未找到 EFI 分区"
            return false
        }
        // 一次授权里依次尝试所有 EFI 分区
        let cmd = parts.map { "/usr/sbin/diskutil mount \($0) >/dev/null 2>&1" }.joined(separator: "; ")
        do {
            _ = try Self.runRoot(cmd)
        } catch {
            appendLog("挂载失败：\(error.localizedDescription)")
            statusText = "挂载失败"
            return false
        }
        refresh()
        if ocPath != nil {
            appendLog("EFI 已挂载于 \(efiVolume ?? "?")")
            return true
        }
        statusText = "挂载后仍未找到 OC"
        return false
    }

    // MARK: - 安装
    func install(kextURL: URL, enable: Bool = true) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: kextURL.path) else { throw DriverError.message("kext 文件不存在") }
        guard kextURL.pathExtension == "kext" else { throw DriverError.message("请选择 .kext 目录或包含 kext 的压缩包") }

        guard let oc = ocPath ?? Self.locateOC() else {
            throw DriverError.message("EFI 未挂载，请先点「挂载 EFI」")
        }

        let infoPath = kextURL.path + "/Contents/Info.plist"
        guard let info = Self.readPlist(infoPath),
              let bundle = info["CFBundleIdentifier"] as? String else {
            throw DriverError.message("无法读取 kext 的 Info.plist")
        }
        let dirName = kextURL.lastPathComponent
        let dest = oc + "/Kexts/" + dirName

        // 1. 备份 config
        try backup(reason: "install-\(dirName)")

        // 2. 复制 kext（先备份同名旧版本）
        var cmds: [String] = []
        cmds.append("mkdir -p \(Self.q(oc + "/Kexts"))")
        if fm.fileExists(atPath: dest) {
            let bak = oc + "/Kexts-Backup/" + dirName + "-" + Self.stamp()
            cmds.append("mkdir -p \(Self.q(oc + "/Kexts-Backup"))")
            cmds.append("mv \(Self.q(dest)) \(Self.q(bak))")
        }
        cmds.append("cp -R \(Self.q(kextURL.path)) \(Self.q(dest))")
        cmds.append("chown -R root:wheel \(Self.q(dest))")
        cmds.append("chmod -R go-w \(Self.q(dest))")
        _ = try Self.runRoot(cmds.joined(separator: " && "))

        // 3. 写 config：登记 + 排序（依赖必须在前）
        var cfg = Self.readPlist(oc + "/config.plist") ?? [:]
        var kernel = (cfg["Kernel"] as? [String: Any]) ?? [:]
        var add = (kernel["Add"] as? [[String: Any]]) ?? []

        let execRel = Self.executablePath(in: dest)
        var entry: [String: Any] = [
            "Arch": "Any",
            "BundlePath": dirName,
            "Comment": "Added by ROG Control Center",
            "Enabled": enable,
            "ExecutablePath": execRel,
            "MaxKernel": "",
            "MinKernel": "",
            "PlistPath": "Contents/Info.plist"
        ]
        if let old = add.firstIndex(where: { ($0["BundlePath"] as? String) == dirName }) {
            // 保留用户已有的 MinKernel / MaxKernel 限制
            entry["MinKernel"] = add[old]["MinKernel"] ?? ""
            entry["MaxKernel"] = add[old]["MaxKernel"] ?? ""
            add[old] = entry
        } else {
            add.append(entry)
            add = Self.reorder(add)
        }
        kernel["Add"] = add
        cfg["Kernel"] = kernel
        try Self.writeConfig(cfg, to: oc + "/config.plist")

        refresh()
        needsRestart = true
        appendLog("已安装 \(dirName)（\(bundle)）")
    }

    /// 依赖排序：Lilu / VirtualSMC 必须在插件之前
    private static func reorder(_ add: [[String: Any]]) -> [[String: Any]] {
        let priority: (String) -> Int = { path in
            let p = path.lowercased()
            if p.hasPrefix("lilu") { return 0 }
            if p.hasPrefix("virtualsmc.kext") { return 1 }
            if p.hasPrefix("virtualsmc") { return 2 }        // 插件
            if p.hasPrefix("whatevergreen") { return 3 }
            if p.hasPrefix("cpupm") || p.hasPrefix("cputopology") { return 4 }
            return 10
        }
        return add.enumerated().sorted { a, b in
            let pa = priority((a.element["BundlePath"] as? String) ?? "")
            let pb = priority((b.element["BundlePath"] as? String) ?? "")
            if pa != pb { return pa < pb }
            return a.offset < b.offset
        }.map(\.element)
    }

    private static func executablePath(in kext: String) -> String {
        let macos = kext + "/Contents/MacOS"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: macos),
              let exe = files.filter({ !$0.hasPrefix(".") }).sorted().first else { return "" }
        return "Contents/MacOS/" + exe
    }

    // MARK: - 启用 / 禁用 / 卸载
    func setEnabled(bundlePath: String, enabled: Bool) throws {
        guard let oc = ocPath ?? Self.locateOC() else { throw DriverError.message("EFI 未挂载") }
        try backup(reason: enabled ? "enable" : "disable")
        var cfg = Self.readPlist(oc + "/config.plist") ?? [:]
        var kernel = (cfg["Kernel"] as? [String: Any]) ?? [:]
        var add = (kernel["Add"] as? [[String: Any]]) ?? []
        var hit = false
        for i in add.indices where (add[i]["BundlePath"] as? String) == bundlePath {
            add[i]["Enabled"] = enabled
            hit = true
        }
        if !hit {
            // 磁盘上有但 config 没登记 → 补登记
            let full = oc + "/Kexts/" + bundlePath
            add.append([
                "Arch": "Any",
                "BundlePath": bundlePath,
                "Comment": "Added by ROG Control Center",
                "Enabled": enabled,
                "ExecutablePath": Self.executablePath(in: full),
                "MaxKernel": "", "MinKernel": "",
                "PlistPath": "Contents/Info.plist"
            ])
            add = Self.reorder(add)
        }
        kernel["Add"] = add
        cfg["Kernel"] = kernel
        try Self.writeConfig(cfg, to: oc + "/config.plist")
        refresh()
        needsRestart = true
        appendLog("\(enabled ? "已启用" : "已禁用") \(bundlePath)")
    }

    func remove(bundlePath: String) throws {
        guard let oc = ocPath ?? Self.locateOC() else { throw DriverError.message("EFI 未挂载") }
        try backup(reason: "remove")
        let dest = oc + "/Kexts/" + bundlePath
        let trash = oc + "/Kexts-Removed/" + bundlePath + "-" + Self.stamp()
        var cmds: [String] = ["mkdir -p \(Self.q(oc + "/Kexts-Removed"))"]
        if FileManager.default.fileExists(atPath: dest) {
            cmds.append("mv \(Self.q(dest)) \(Self.q(trash))")
        }
        _ = try Self.runRoot(cmds.joined(separator: " && "))

        var cfg = Self.readPlist(oc + "/config.plist") ?? [:]
        var kernel = (cfg["Kernel"] as? [String: Any]) ?? [:]
        var add = (kernel["Add"] as? [[String: Any]]) ?? []
        add.removeAll { ($0["BundlePath"] as? String) == bundlePath }
        kernel["Add"] = add
        cfg["Kernel"] = kernel
        try Self.writeConfig(cfg, to: oc + "/config.plist")

        refresh()
        needsRestart = true
        appendLog("已移除 \(bundlePath)（原文件在 Kexts-Removed）")
    }

    // MARK: - 备份
    func backup(reason: String = "manual") throws {
        guard let oc = ocPath ?? Self.locateOC() else { throw DriverError.message("EFI 未挂载") }
        let dir = oc + "/ConfigBackups"
        let name = "config-\(Self.stamp())-\(reason).plist"
        let cmds = [
            "mkdir -p \(Self.q(dir))",
            "cp \(Self.q(oc + "/config.plist")) \(Self.q(dir + "/" + name))"
        ]
        _ = try Self.runRoot(cmds.joined(separator: " && "))
        appendLog("已备份配置 → \(name)")
    }

    /// 用指定备份覆盖 config.plist
    func restoreBackup(named name: String) throws {
        guard let oc = ocPath ?? Self.locateOC() else { throw DriverError.message("EFI 未挂载") }
        let src = oc + "/ConfigBackups/" + name
        guard FileManager.default.fileExists(atPath: src) else {
            throw DriverError.message("备份文件不存在：\(name)")
        }
        let cmds = [
            "cp \(Self.q(src)) \(Self.q(oc + "/config.plist"))",
            "chown root:wheel \(Self.q(oc + "/config.plist"))",
            "chmod 644 \(Self.q(oc + "/config.plist"))"
        ]
        _ = try Self.runRoot(cmds.joined(separator: " && "))
        refresh()
        needsRestart = true
        appendLog("已恢复配置备份 \(name)")
    }

    func backupList() -> [String] {
        guard let oc = ocPath else { return [] }
        let dir = oc + "/ConfigBackups"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files.filter { $0.hasSuffix(".plist") }.sorted().reversed()
    }

    // MARK: - 下载（GitHub release）
    struct ReleaseAsset { let name: String; let url: String }

    func latestAsset(for spec: DriverSpec) async throws -> ReleaseAsset {
        guard let repo = spec.repo else { throw DriverError.message("该驱动不支持自动下载") }
        guard let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw DriverError.message("地址无效")
        }
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw DriverError.message("GitHub 接口返回 \(((resp as? HTTPURLResponse)?.statusCode) ?? -1)，请检查网络")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            throw DriverError.message("解析发布信息失败")
        }
        let zips = assets.compactMap { a -> ReleaseAsset? in
            guard let n = a["name"] as? String, n.lowercased().hasSuffix(".zip"),
                  let u = a["browser_download_url"] as? String else { return nil }
            return ReleaseAsset(name: n, url: u)
        }
        // 优先 RELEASE 包，且名字里带驱动名
        if let best = zips.first(where: { $0.name.uppercased().contains("RELEASE") && $0.name.localizedCaseInsensitiveContains(spec.name) })
            ?? zips.first(where: { $0.name.uppercased().contains("RELEASE") })
            ?? zips.first {
            return best
        }
        throw DriverError.message("该发布页没有 zip 资产，请到官网手动下载")
    }

    /// 安装应用内置的 kext（离线，随 App 打包在 Contents/Resources/Kexts，支持 .kext 或 .zip 载荷）
    func installBundled(spec: DriverSpec) throws {
        let fm = FileManager.default
        guard let res = Bundle.main.resourceURL else {
            throw DriverError.message("应用资源目录缺失")
        }
        let dir = res.appendingPathComponent("Kexts", isDirectory: true)
        let payloads = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "zip" || $0.pathExtension == "kext" } ?? []
        guard !payloads.isEmpty else {
            throw DriverError.message("应用内未找到内置驱动，请重新安装 App")
        }
        guard let payload = payloads.first(where: {
            $0.lastPathComponent.localizedCaseInsensitiveContains(spec.name)
        }) ?? payloads.first else {
            throw DriverError.message("内置驱动缺失：\(spec.name)")
        }

        // 解到临时目录（应用包内文件被签名保护，不能直接改属性）
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("rog-bundled-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let kext: URL
        if payload.pathExtension == "zip" {
            try Self.unzip(payload, to: tmp)
            guard let found = Self.findKext(in: tmp, named: spec.name) ?? Self.findKext(in: tmp, named: "") else {
                throw DriverError.message("内置压缩包里没有 .kext")
            }
            kext = found
        } else {
            let stage = tmp.appendingPathComponent(payload.lastPathComponent)
            try fm.copyItem(at: payload, to: stage)
            kext = stage
        }

        try install(kextURL: kext)
        appendLog("已安装内置驱动 \(payload.lastPathComponent)")
    }

    func downloadAndInstall(spec: DriverSpec) async throws {
        busy = true
        statusText = "正在获取 \(spec.name) 发布信息…"
        defer { busy = false }
        let asset = try await latestAsset(for: spec)
        appendLog("发现 \(asset.name)")

        statusText = "正在下载 \(asset.name)…"
        guard let url = URL(string: asset.url) else { throw DriverError.message("下载地址无效") }
        let (tmp, _) = try await URLSession.shared.download(from: url)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("rog-driver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent(asset.name)
        try FileManager.default.moveItem(at: tmp, to: zip)
        appendLog("下载完成 \(zip.lastPathComponent)")

        statusText = "正在解压…"
        try Self.unzip(zip, to: work)
        guard let kext = Self.findKext(in: work, named: spec.name) else {
            throw DriverError.message("压缩包里没有找到 \(spec.name).kext")
        }

        statusText = "正在写入 EFI…"
        try install(kextURL: kext)
        statusText = "已安装 \(spec.name) · 重启后生效"
    }

    static func unzip(_ zip: URL, to dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw DriverError.message("解压失败：\(msg)")
        }
    }

    static func findKext(in dir: URL, named: String) -> URL? {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        var all: [URL] = []
        for case let u as URL in e where u.pathExtension == "kext" {
            all.append(u)
        }
        if named.isEmpty { return all.first }
        if let exact = all.first(where: { $0.lastPathComponent.caseInsensitiveCompare(named + ".kext") == .orderedSame }) {
            return exact
        }
        return all.first
    }

    // MARK: - 权限与文件
    enum DriverError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let m): return m }
        }
    }

    /// 用管理员权限执行 shell，返回 stdout
    static func runRoot(_ command: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        p.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            let e = String(data: errData, encoding: .utf8) ?? ""
            if e.contains("User canceled") || e.contains("-128") {
                throw DriverError.message("已取消授权")
            }
            throw DriverError.message(e.isEmpty ? "命令执行失败" : e.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text
    }

    static func q(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    static func readPlist(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    /// 写入 config.plist：先写临时文件，再以 root 覆盖，保持属主正确
    static func writeConfig(_ cfg: [String: Any], to path: String) throws {
        // 保持原有格式（XML / 二进制）
        var fmt = PropertyListSerialization.PropertyListFormat.xml
        if let head = FileManager.default.contents(atPath: path)?.prefix(8), head.starts(with: Array("bplist".utf8)) {
            fmt = .binary
        }
        let data = try PropertyListSerialization.data(fromPropertyList: cfg, format: fmt, options: 0)
        let tmp = NSTemporaryDirectory() + "rog-config-\(UUID().uuidString).plist"
        try data.write(to: URL(fileURLWithPath: tmp))
        let cmds = [
            "cp \(q(tmp)) \(q(path))",
            "chown root:wheel \(q(path))",
            "chmod 644 \(q(path))",
            "rm -f \(q(tmp))"
        ]
        _ = try runRoot(cmds.joined(separator: " && "))
    }

    // MARK: - 内核已加载列表（kextstat）
    static func kextstat() -> Set<String> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/kextstat")
        p.arguments = []
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var set = Set<String>()
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 6 else { continue }
            let name = String(cols[5])
            if name.contains(".") { set.insert(name) }
        }
        return set
    }
}
