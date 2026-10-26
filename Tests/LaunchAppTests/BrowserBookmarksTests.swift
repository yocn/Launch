import Foundation
import XCTest
@testable import LaunchApp

final class BrowserBookmarksTests: XCTestCase {
    func testParsesChromeRootsAndNestedFolders() throws {
        let json = #"""
        {"roots":{
          "bookmark_bar":{"type":"folder","name":"书签栏","children":[
            {"type":"url","name":"百度","url":"https://www.baidu.com/"},
            {"type":"folder","name":"工作","children":[{"type":"url","name":"文档","url":"https://example.com/doc"}]},
            {"type":"url","name":"脚本","url":"javascript:alert(1)"}]},
          "other":{"type":"folder","name":"其他书签","children":[]},
          "synced":{"type":"folder","name":"移动设备书签","children":[{"type":"url","name":"手机","url":"http://m.example.com"}]}}}
        """#
        let tree = try BrowserBookmarks.parseChrome(Data(json.utf8))
        XCTAssertEqual(tree.map(\.name), ["书签栏", "移动设备书签"])
        XCTAssertEqual(tree[0].children.map(\.name), ["百度", "工作"])
        XCTAssertEqual(tree[0].children[1].children.first?.url?.absoluteString, "https://example.com/doc")
    }

    func testParsesSafariPlistAndSkipsReadingList() throws {
        let plist: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Children": [
                ["WebBookmarkType": "WebBookmarkTypeList", "Title": "BookmarksBar", "Children": [
                    ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://apple.com", "URIDictionary": ["title": "Apple"]],
                    ["WebBookmarkType": "WebBookmarkTypeList", "Title": "空文件夹", "Children": []],
                ]],
                ["WebBookmarkType": "WebBookmarkTypeList", "Title": "com.apple.ReadingList", "Children": [
                    ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://later.example.com", "URIDictionary": ["title": "稍后"]],
                ]],
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let tree = try BrowserBookmarks.parseSafari(data)
        XCTAssertEqual(tree.map(\.name), ["个人收藏"])
        XCTAssertEqual(tree[0].children.map(\.name), ["Apple"])
    }

    func testFlattenedSearchAndDuplicateMarking() {
        let tree = [BookmarkNode.folder("栏", [.link("百度", URL(string: "https://baidu.com")!), .link("GitHub", URL(string: "https://github.com")!)])]
        XCTAssertEqual(BrowserBookmarks.links(in: tree, matching: "git").map(\.name), ["GitHub"])
        XCTAssertEqual(BrowserBookmarks.links(in: tree, matching: "baidu.com").map(\.name), ["百度"])
        XCTAssertEqual(BrowserBookmarks.links(in: tree, matching: "").count, 2)
    }
}
