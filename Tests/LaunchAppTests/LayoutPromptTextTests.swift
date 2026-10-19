import LaunchCore
import XCTest
@testable import LaunchApp

final class LayoutPromptTextTests: XCTestCase {
    func testSummaryMentionsMissingAndNewApps() {
        let summary = LaunchpadImportSummary(pageCount: 2, folderCount: 3, appCount: 96, installedCount: 81, newAppCount: 25)

        XCTAssertEqual(
            LayoutPromptText.summary(summary),
            "旧 Launchpad 布局：2 页、3 个文件夹、96 个应用。已安装 81 个；未安装 15 个，会保留位置，重新安装后回到原处。另有 25 个新应用会排在最后。"
        )
    }

    func testSummaryOmitsZeroCounts() {
        let summary = LaunchpadImportSummary(pageCount: 1, folderCount: 0, appCount: 4, installedCount: 4, newAppCount: 0)

        XCTAssertEqual(
            LayoutPromptText.summary(summary),
            "旧 Launchpad 布局：1 页、0 个文件夹、4 个应用。已安装 4 个。"
        )
    }
}
