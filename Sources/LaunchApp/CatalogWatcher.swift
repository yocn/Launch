import CoreServices
import Foundation
import LaunchCore

final class CatalogWatcher {
    private let roots: [URL]
    private let scan: @Sendable ([URL]) -> [CatalogApp]
    private let onChange: @MainActor @Sendable ([CatalogApp]) -> Void
    private let queue = DispatchQueue(label: "dev.yocn.launch.catalog-watcher")
    private let coalesceDelay: TimeInterval
    private let state = ScanState()
    private var stream: FSEventStreamRef?

    init(
        roots: [URL],
        coalesceDelay: TimeInterval = 0.5,
        scan: @escaping @Sendable ([URL]) -> [CatalogApp] = { roots in
            (try? AppCatalog().scan(roots: roots)) ?? []
        },
        onChange: @escaping @MainActor @Sendable ([CatalogApp]) -> Void
    ) {
        self.roots = roots
        self.coalesceDelay = coalesceDelay
        self.scan = scan
        self.onChange = onChange
    }

    deinit {
        guard let stream else {
            return
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    func start() {
        scheduleScan(after: 0)
        // FSEvents 需要真实路径，临时目录等位于 /var -> /private/var 的符号链接下
        let watchedPaths = roots
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { $0.resolvingSymlinksInPath().path }
        guard stream == nil, !watchedPaths.isEmpty else {
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else {
                return
            }
            Unmanaged<CatalogWatcher>.fromOpaque(info).takeUnretainedValue().rescan()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            watchedPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else {
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    // 改动分散在多个目录时，同一时刻会收到多次变化通知，合并成一次扫描；结果没变不交给主线程
    func rescan() {
        scheduleScan(after: coalesceDelay)
    }

    private func scheduleScan(after delay: TimeInterval) {
        let (roots, scan, onChange, state, queue) = (roots, scan, onChange, state, queue)
        queue.async {
            guard !state.isPending else {
                return
            }
            state.isPending = true
            queue.asyncAfter(deadline: .now() + delay) {
                state.isPending = false
                let apps = scan(roots)
                guard apps != state.lastDelivered else {
                    return
                }
                state.lastDelivered = apps
                Task { @MainActor in
                    onChange(apps)
                }
            }
        }
    }
}

// 只在监听器的串行队列上读写
private final class ScanState: @unchecked Sendable {
    var isPending = false
    var lastDelivered: [CatalogApp]?
}
