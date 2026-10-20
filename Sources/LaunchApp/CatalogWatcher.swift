import CoreServices
import Foundation
import LaunchCore

final class CatalogWatcher {
    private let roots: [URL]
    private let scan: @Sendable ([URL]) -> [CatalogApp]
    private let onChange: @MainActor @Sendable ([CatalogApp]) -> Void
    private let queue = DispatchQueue(label: "dev.yocn.launch.catalog-watcher")
    private var stream: FSEventStreamRef?

    init(
        roots: [URL],
        scan: @escaping @Sendable ([URL]) -> [CatalogApp] = { roots in
            (try? AppCatalog().scan(roots: roots)) ?? []
        },
        onChange: @escaping @MainActor @Sendable ([CatalogApp]) -> Void
    ) {
        self.roots = roots
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
        rescan()
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

    func rescan() {
        let roots = roots
        let scan = scan
        let onChange = onChange
        queue.async {
            let apps = scan(roots)
            Task { @MainActor in
                onChange(apps)
            }
        }
    }
}
