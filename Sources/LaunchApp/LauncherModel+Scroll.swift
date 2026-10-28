import CoreGraphics
import Foundation
import LaunchCore

// 滚动浏览、首页布局与拖动时的自动滚动
extension LauncherModel {
    func updateHomeLayout(_ layout: LauncherHomeLayout) {
        homeLayout = layout
    }

    func updateGridFrame(_ frame: CGRect) {
        gridFrame = frame
    }

    func updateDisplayMode(_ mode: DisplayMode) {
        if mode != displayMode {
            displayMode = mode
        }
    }

    func updateBrowsingStyle(_ style: BrowsingStyle) {
        guard style != browsingStyle else {
            return
        }
        browsingStyle = style
        pageFrames = [:]
        setGridPage(clampedPage(currentPage), animated: false)
    }

    // 滚动浏览时 gridFrame 是滚动区域，各页位置由视图逐页上报
    func updatePageFrame(_ frame: CGRect, page: Int) {
        pageFrames[page] = frame
        followScroll()
    }

    // 当前页仍有部分可见时不变；完全滚出后换成最上面可见的页，键盘选中随之清掉
    private func followScroll() {
        guard browsingStyle == .scroll, dragSession == nil else {
            return
        }
        let visible = visibleHomePages().map(\.page)
        guard !visible.contains(currentPage), let top = visible.min() else {
            return
        }
        currentPage = top
        selectedIndex = nil
    }

    func requestScroll(_ kind: ScrollRequest.Kind) {
        scrollSerial += 1
        scrollRequest = ScrollRequest(kind: kind, serial: scrollSerial)
    }

    func visibleHomePages() -> [(page: Int, frame: CGRect)] {
        guard browsingStyle == .scroll else {
            return pages.indices.contains(currentPage) ? [(currentPage, gridFrame)] : []
        }
        return pageFrames
            .filter { pages.indices.contains($0.key) && $0.value.intersects(gridFrame) }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    // 分页时屏幕上只有当前页；滚动时按指针所在页，拖动时取最近的页
    func homePage(at point: CGPoint, nearest: Bool = false) -> (page: Int, frame: CGRect)? {
        let candidates = visibleHomePages()
        guard browsingStyle == .scroll else {
            return candidates.first
        }
        let spacing = homeLayout?.folderRowSpacing ?? 0
        if let hit = candidates.first(where: { $0.frame.insetBy(dx: 0, dy: -spacing / 2).contains(point) }) {
            return hit
        }
        guard nearest else {
            return nil
        }
        func distance(_ frame: CGRect) -> CGFloat {
            point.y < frame.minY ? frame.minY - point.y : max(point.y - frame.maxY, 0)
        }
        return candidates.min { distance($0.frame) < distance($1.frame) }
    }

    func homeFrame(ofPage page: Int) -> CGRect? {
        browsingStyle == .scroll ? pageFrames[page] : (page == currentPage ? gridFrame : nil)
    }

    func homeTester(_ frame: CGRect, layout: LauncherHomeLayout) -> GridHitTester {
        guard browsingStyle == .scroll else {
            return GridHitTester(layout: layout, frame: frame, topInset: layout.gridTopInset)
        }
        var tester = GridHitTester(layout: layout, frame: frame, rowSpacing: layout.folderRowSpacing)
        tester.detectsPageEdges = false
        return tester
    }

    // 滚动浏览时拖到滚动区上下边缘附近自动滚动，越靠边越快
    func autoScroll(at point: CGPoint, now: TimeInterval) {
        let zone: CGFloat = 80
        let fastest: CGFloat = 1200
        let speed: CGFloat
        if point.y > gridFrame.maxY - zone {
            speed = fastest * min(1, (point.y - (gridFrame.maxY - zone)) / zone)
        } else if point.y < gridFrame.minY + zone {
            speed = -fastest * min(1, (gridFrame.minY + zone - point.y) / zone)
        } else {
            lastAutoScroll = nil
            return
        }
        let elapsed = lastAutoScroll.map { min(max(now - $0, 0), 0.1) } ?? 1.0 / 30
        lastAutoScroll = now
        requestScroll(.by(speed * elapsed))
    }

    func updateFolderGridFrame(_ frame: CGRect) {
        folderGridFrame = frame
    }
}
