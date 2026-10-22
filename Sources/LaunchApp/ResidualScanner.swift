import CryptoKit
import Darwin
import Foundation
import LaunchCore
import Security

struct ResidualSigning: Equatable, Sendable {
    let identifier: String
    let team: String
    var groups: [String]
    var codeHash = ""

    static func read(_ url: URL) -> Self? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), requirement) == errSecSuccess else {
            return nil
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else { return nil }
        let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let groups = entitlements?["com.apple.security.application-groups"] as? [String] ?? []
        return Self(identifier: identifier, team: team, groups: groups,
                    codeHash: (info[kSecCodeInfoUnique as String] as? Data)?.base64EncodedString() ?? "")
    }
}

struct ResidualSnapshot: Codable, Equatable, Sendable {
    let digest: String
    let bytes: Int64
}

struct ResidualItem: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let category: String
    let evidence: String
    let snapshot: ResidualSnapshot?
    let blockedReason: String?
    var isSelectable: Bool { blockedReason == nil && snapshot != nil }
}

struct ResidualPlan: Sendable {
    let app: CatalogApp
    let appSnapshot: ResidualSnapshot
    let infoDigest: String
    let signing: ResidualSigning?
    let items: [ResidualItem]
    let notices: [String]
    var defaultSelection: Set<String> { [] }
}

enum ResidualSafetyError: LocalizedError {
    case unsafe(String)
    var errorDescription: String? {
        switch self { case .unsafe(let message): message }
    }
}

// 只扫描完整 ID 的固定位置；名称猜测和共享组只展示，永不进入可执行清单。
struct ResidualScanner: Sendable {
    let home: URL
    let applicationRoots: [URL]
    var signing: @Sendable (URL) -> ResidualSigning? = ResidualSigning.read
    var entryLimit = 15_000
    var timeLimit: TimeInterval = 3

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         applicationRoots: [URL] = ApplicationSources.defaultRoots(),
         signing: @escaping @Sendable (URL) -> ResidualSigning? = ResidualSigning.read) {
        self.home = Self.canonicalURL(home)
        self.applicationRoots = applicationRoots
        self.signing = signing
    }

    func scan(_ app: CatalogApp) throws -> ResidualPlan {
        let url = URL(fileURLWithPath: app.identity.path)
        try validateApplicationPath(url)
        let appSnapshot = try snapshot(url, recursive: false)
        let info = try Data(contentsOf: url.appending(path: "Contents/Info.plist"))
        let proof = signing(url)
        guard let identifier = app.identity.bundleIdentifier, Self.validIdentifier(identifier),
              identifier.split(separator: ".").count >= 3, !identifier.lowercased().hasPrefix("com.apple.") else {
            return ResidualPlan(app: app, appSnapshot: appSnapshot, infoDigest: Self.digest(info), signing: proof,
                                items: [], notices: ["应用标识无法安全核对，仅卸载应用本体。"])
        }
        let inventory = inventory(excluding: url, identifier: identifier)
        let metadataID = Self.metadata(url)?["CFBundleIdentifier"] as? String
        let trustReason: String?
        if proof == nil || proof?.identifier != identifier || metadataID != identifier {
            trustReason = "无法核对有效签名与应用标识，仅允许卸载应用本体"
        } else if !inventory.complete {
            trustReason = "应用来源检查不完整，无法排除其他应用使用这些文件"
        } else if inventory.duplicate {
            trustReason = "仍有相同标识的其他安装副本，可能共用这些数据"
        } else {
            trustReason = nil
        }
        struct Candidate {
            let relative: String
            let category: String
            let evidence: String
            let blocked: String?
        }
        var candidates = [
            Candidate(relative: "Caches/\(identifier)", category: "缓存", evidence: "目录名与完整应用标识一致", blocked: nil),
            Candidate(relative: "Logs/\(identifier)", category: "日志", evidence: "目录名与完整应用标识一致", blocked: nil),
            Candidate(relative: "Preferences/\(identifier).plist", category: "偏好设置", evidence: "文件名与完整应用标识一致；可能包含账号与个人设置", blocked: nil),
            Candidate(relative: "Saved Application State/\(identifier).savedState", category: "窗口状态", evidence: "目录名与完整应用标识一致", blocked: nil),
            Candidate(relative: "Application Support/\(identifier)", category: "应用数据", evidence: "目录名与完整应用标识一致；可能包含历史记录和用户数据", blocked: nil),
            Candidate(relative: "Containers/\(identifier)", category: "应用容器", evidence: "完整应用标识及容器所属标识；可能包含用户数据", blocked: nil),
        ]
        for group in proof?.groups ?? [] where Self.validIdentifier(group) {
            candidates.append(Candidate(relative: "Group Containers/\(group)", category: "共享容器",
                                        evidence: "应用签名声明的共享组", blocked: "共享容器可能被其他应用使用，本版保留"))
        }
        let names = [app.displayName, url.deletingPathExtension().lastPathComponent,
                     Self.metadata(url)?["CFBundleName"] as? String ?? ""]
        for name in Set(names) where !name.isEmpty && name != identifier && Self.safeComponent(name) {
            candidates.append(Candidate(relative: "Application Support/\(name)", category: "可能相关的数据",
                                        evidence: "仅名称相同，不能确认独占归属", blocked: "名称匹配不足以证明归属，本版保留"))
        }
        let manager = FileManager.default
        var items: [ResidualItem] = []
        var notices: [String] = []
        for candidate in candidates {
            let candidateURL = home.appending(path: "Library/" + candidate.relative)
            // 不先用 fileExists；它会把权限错误和断链误报为不存在。
            do {
                _ = try manager.attributesOfItem(atPath: candidateURL.path)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
                continue
            } catch {
                notices.append("无法检查 \(candidateURL.path)：\(error.localizedDescription)")
                continue
            }
            var blocked = candidate.blocked ?? trustReason
            var captured: ResidualSnapshot?
            do {
                if candidate.category == "共享容器" {
                    items.append(ResidualItem(url: candidateURL, category: candidate.category, evidence: candidate.evidence,
                                              snapshot: nil, blockedReason: candidate.blocked))
                    continue
                }
                try validateCandidatePath(candidateURL)
                captured = try snapshot(candidateURL)
                if !manager.isWritableFile(atPath: candidateURL.path) || !manager.isWritableFile(atPath: candidateURL.deletingLastPathComponent().path) {
                    blocked = "当前用户无法直接移动，本版保留"
                }
                if candidate.category == "应用容器" {
                    let metadata = candidateURL.appending(path: ".com.apple.containermanagerd.metadata.plist")
                    let data = try Data(contentsOf: metadata)
                    let container = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                    if container?["MCMMetadataIdentifier"] as? String != identifier {
                        blocked = "容器所属标识无法核对，本版保留"
                    }
                }
            } catch {
                blocked = "无法安全检查：\(error.localizedDescription)"
            }
            items.append(ResidualItem(url: candidateURL, category: candidate.category, evidence: candidate.evidence,
                                      snapshot: captured, blockedReason: blocked))
        }
        if let trustReason { notices.insert(trustReason, at: 0) }
        return ResidualPlan(app: app, appSnapshot: appSnapshot, infoDigest: Self.digest(info), signing: proof,
                            items: items, notices: notices)
    }

    func revalidate(_ item: ResidualItem) throws {
        guard item.isSelectable else { throw ResidualSafetyError.unsafe("该项目不可清理") }
        try validateCandidatePath(item.url)
        guard try snapshot(item.url) == item.snapshot else {
            throw ResidualSafetyError.unsafe("文件或目录内容已变化，请重新扫描")
        }
    }

    func revalidateApp(_ plan: ResidualPlan, needsResiduals: Bool) throws {
        let url = URL(fileURLWithPath: plan.app.identity.path)
        try validateApplicationPath(url)
        guard try snapshot(url, recursive: false) == plan.appSnapshot,
              Self.digest(try Data(contentsOf: url.appending(path: "Contents/Info.plist"))) == plan.infoDigest else {
            throw ResidualSafetyError.unsafe("应用本体或标识已变化，请重新扫描")
        }
        if needsResiduals {
            guard let identifier = plan.app.identity.bundleIdentifier,
                  let expected = plan.signing, signing(url) == expected else {
                throw ResidualSafetyError.unsafe("应用签名发生变化，已停止清理")
            }
            let result = inventory(excluding: url, identifier: identifier)
            guard result.complete && !result.duplicate else {
                throw ResidualSafetyError.unsafe("无法排除其他安装副本，已停止清理")
            }
        }
    }

    func residualsStillExclusive(_ plan: ResidualPlan) -> Bool {
        guard let identifier = plan.app.identity.bundleIdentifier else { return false }
        let result = inventory(excluding: URL(fileURLWithPath: plan.app.identity.path), identifier: identifier)
        return result.complete && !result.duplicate
    }

    private func validateApplicationPath(_ url: URL) throws {
        guard url.pathExtension == "app", !url.path.hasPrefix("/System/"),
              Self.canonicalURL(url) != Self.canonicalURL(Bundle.main.bundleURL),
              let root = applicationRoots.first(where: { url.path.hasPrefix($0.path + "/") }) else {
            throw ResidualSafetyError.unsafe("应用不在允许的来源内")
        }
        let parts = String(url.path.dropFirst(root.path.count + 1)).split(separator: "/")
        var current = root
        for part in parts {
            current.append(path: String(part))
            let attrs = try FileManager.default.attributesOfItem(atPath: current.path)
            guard attrs[.type] as? FileAttributeType == .typeDirectory else {
                throw ResidualSafetyError.unsafe("应用路径包含链接或异常目录")
            }
        }
    }

    private func validateCandidatePath(_ url: URL) throws {
        let library = home.appending(path: "Library")
        let relative = String(url.path.dropFirst(library.path.count + 1))
        let parts = relative.split(separator: "/").map(String.init)
        let allowed = ["Caches", "Logs", "Preferences", "Saved Application State", "Application Support", "Containers"]
        guard url.path.hasPrefix(library.path + "/"), parts.count == 2, allowed.contains(parts[0]),
              parts.allSatisfy(Self.safeComponent) else {
            throw ResidualSafetyError.unsafe("路径不在可清理的固定目录内")
        }
        var current = home
        for part in ["Library"] + parts {
            current.append(path: part)
            let attrs = try FileManager.default.attributesOfItem(atPath: current.path)
            guard attrs[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw ResidualSafetyError.unsafe("路径包含符号链接")
            }
        }
        guard url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else {
            throw ResidualSafetyError.unsafe("路径指向其他位置")
        }
    }

    // 不读取文件正文；摘要包含祖先与各节点身份、时间和大小，检测换目录、换文件和内容变化。
    func snapshot(_ url: URL, recursive: Bool = true) throws -> ResidualSnapshot {
        let manager = FileManager.default
        guard try manager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType != .typeSymbolicLink else {
            throw ResidualSafetyError.unsafe("文件是符号链接")
        }
        let url = Self.canonicalURL(url)
        let start = ProcessInfo.processInfo.systemUptime
        var nodes = [url]
        var scanError: Error?
        let root = try manager.attributesOfItem(atPath: url.path)
        if recursive, root[.type] as? FileAttributeType == .typeDirectory {
            guard let enumeration = manager.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in
                scanError = error
                return false
            }) else { throw ResidualSafetyError.unsafe("目录无法读取") }
            while let child = enumeration.nextObject() as? URL {
                guard nodes.count < entryLimit, ProcessInfo.processInfo.systemUptime - start < timeLimit else {
                    throw ResidualSafetyError.unsafe("目录过大或检查超时，本版保留")
                }
                nodes.append(child)
                let attrs = try manager.attributesOfItem(atPath: child.path)
                if attrs[.type] as? FileAttributeType == .typeSymbolicLink { enumeration.skipDescendants() }
            }
            if let scanError { throw scanError }
        }
        var records: [String] = []
        var bytes: Int64 = 0
        for node in nodes.sorted(by: { $0.path < $1.path }) {
            let attrs = try manager.attributesOfItem(atPath: node.path)
            let kind = attrs[.type] as? FileAttributeType
            guard kind == .typeDirectory || kind == .typeRegular,
                  attrs[.systemNumber] as? NSNumber == root[.systemNumber] as? NSNumber,
                  manager.isReadableFile(atPath: node.path),
                  kind != .typeRegular || (attrs[.referenceCount] as? NSNumber)?.intValue == 1 else {
                throw ResidualSafetyError.unsafe("含链接、特殊文件、跨卷或无法读取的内容")
            }
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            if kind == .typeRegular { bytes += size }
            records.append("\(node.path)|\(attrs[.systemNumber] ?? "")|\(attrs[.systemFileNumber] ?? "")|\(kind?.rawValue ?? "")|\(size)|\((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\((attrs[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0)")
        }
        // 目录父级的 mtime 会因其他项目移动改变，只比较身份，不比较时间。
        var parent = url.deletingLastPathComponent()
        for _ in 0 ..< 64 {
            let attrs = try manager.attributesOfItem(atPath: parent.path)
            guard attrs[.type] as? FileAttributeType == .typeDirectory else { throw ResidualSafetyError.unsafe("祖先目录不是普通目录：\(parent.path)") }
            records.append("\(parent.path)|\(attrs[.systemNumber] ?? "")|\(attrs[.systemFileNumber] ?? "")")
            if parent.path == "/" { break }
            parent.deleteLastPathComponent()
        }
        return ResidualSnapshot(digest: Self.digest(Data(records.joined(separator: "\n").utf8)), bytes: bytes)
    }

    private func inventory(excluding appURL: URL, identifier: String) -> (complete: Bool, duplicate: Bool) {
        let manager = FileManager.default
        var complete = true
        var count = 0
        let start = ProcessInfo.processInfo.systemUptime
        for root in applicationRoots {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
                // 可选目录不存在正常；无法读取的目录不能认为没有应用。
                if !manager.isReadableFile(atPath: root.deletingLastPathComponent().path) { complete = false }
                continue
            }
            guard isDirectory.boolValue, manager.isReadableFile(atPath: root.path),
                  manager.isExecutableFile(atPath: root.path),
                  let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in
                complete = false
                return true
            }) else { complete = false; continue }
            while let url = enumerator.nextObject() as? URL {
                count += 1
                if count > entryLimit || ProcessInfo.processInfo.systemUptime - start > timeLimit { return (false, false) }
                guard url.pathExtension == "app" else { continue }
                enumerator.skipDescendants()
                if url.resolvingSymlinksInPath().standardizedFileURL == appURL.resolvingSymlinksInPath().standardizedFileURL { continue }
                guard let metadata = Self.metadata(url) else { complete = false; continue }
                if let other = metadata["CFBundleIdentifier"] as? String {
                    let otherID = other.lowercased()
                    let targetID = identifier.lowercased()
                    // 默认磁盘不区分大小写；独立的子标识应用也可能使用父应用的数据。
                    if otherID == targetID || otherID.hasPrefix(targetID + ".") { return (complete, true) }
                }
            }
        }
        return (complete, false)
    }

    private static func metadata(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url.appending(path: "Contents/Info.plist")) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private static func validIdentifier(_ identifier: String) -> Bool {
        identifier.utf8.count <= 200 && identifier.contains(".") && identifier.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0) || $0 == 45 || $0 == 95 }
        }
    }

    private static func safeComponent(_ name: String) -> Bool {
        name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0") && !name.contains(":")
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    // Foundation 在 macOS 上会保留 /var 别名，使用 realpath 得到实际祖先路径。
    private static func canonicalURL(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }
}
