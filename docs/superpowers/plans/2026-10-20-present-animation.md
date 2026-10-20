# 启动器唤起与隐藏动画 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 启动器唤起时背景淡入、内容从 1.04 倍收到 1 倍并淡入；隐藏时反向，动画结束后再收起面板。

**Architecture:** `LauncherModel.isPresented` 驱动 SwiftUI 动画（背景只淡入淡出，内容缩放加淡入淡出）；`ScreenPresenter` 用 `DelayedDismissal` 把收起推迟到动画结束，动画中视为已关闭以便再次唤起时反向；`PresentationTransition` 集中动画参数。

**Tech Stack:** Swift 6，SwiftUI（`animation(_:body:)`、`accessibilityReduceMotion`），AppKit，XCTest。

**Spec:** `docs/superpowers/specs/2026-10-20-present-animation-design.md`

命令：`swift build 2>&1 | grep -E "error:|warning:|Build complete"`；`swift test 2>&1 | grep -E "error:|with [1-9][0-9]* failures|Executed [0-9]+ tests" | awk '/Executed/{print $2} /error|with [1-9]/{print}' | sort -n | uniq | tail -3`；安装 `LAUNCH_SIGN_IDENTITY="Apple Development: zhaoyingkun@163.com" ./scripts/build-app.sh --install`。

---

### Task 1: DelayedDismissal 与动画参数

**Files:**
- Create: `Sources/LaunchApp/PresentationTransition.swift`
- Test: `Tests/LaunchAppTests/DelayedDismissalTests.swift`

- [ ] **Step 1: 失败测试**

```swift
import XCTest
@testable import LaunchApp

@MainActor
private final class ManualScheduler {
    var delays: [TimeInterval] = []
    var actions: [@MainActor @Sendable () -> Void] = []

    func run() {
        let current = actions
        actions = []
        current.forEach { $0() }
    }
}

@MainActor
private final class Counter {
    var values: [String] = []
}

@MainActor
final class DelayedDismissalTests: XCTestCase {
    private func make(_ scheduler: ManualScheduler) -> DelayedDismissal {
        DelayedDismissal { delay, action in
            scheduler.delays.append(delay)
            scheduler.actions.append(action)
        }
    }

    func testRunsActionAfterDelay() {
        let scheduler = ManualScheduler()
        let counter = Counter()
        let dismissal = make(scheduler)

        dismissal.start(after: 0.22) { counter.values.append("hide") }
        XCTAssertTrue(dismissal.isPending)
        scheduler.run()

        XCTAssertEqual(counter.values, ["hide"])
        XCTAssertFalse(dismissal.isPending)
        XCTAssertEqual(scheduler.delays, [0.22])
    }

    func testCancelPreventsAction() {
        let scheduler = ManualScheduler()
        let counter = Counter()
        let dismissal = make(scheduler)

        dismissal.start(after: 0.22) { counter.values.append("hide") }
        dismissal.cancel()
        scheduler.run()

        XCTAssertEqual(counter.values, [])
        XCTAssertFalse(dismissal.isPending)
    }

    func testRestartRunsOnlyLatest() {
        let scheduler = ManualScheduler()
        let counter = Counter()
        let dismissal = make(scheduler)

        dismissal.start(after: 0.22) { counter.values.append("first") }
        dismissal.start(after: 0.22) { counter.values.append("second") }
        scheduler.run()

        XCTAssertEqual(counter.values, ["second"])
    }
}
```

- [ ] **Step 2: 确认失败**：`swift test --filter DelayedDismissalTests` 编译错误，找不到 `DelayedDismissal`。

- [ ] **Step 3: 实现** `Sources/LaunchApp/PresentationTransition.swift`

```swift
import SwiftUI

// 参数按 LaunchOS 录屏逐帧测量
enum PresentationTransition {
    static let hiddenScale: CGFloat = 1.04
    static let hideDuration: TimeInterval = 0.22

    static func backgroundAnimation(presented: Bool) -> Animation {
        presented ? .easeOut(duration: 0.25) : .easeIn(duration: hideDuration)
    }

    static func scaleAnimation(presented: Bool) -> Animation {
        presented ? .easeOut(duration: 0.25) : .easeIn(duration: 0.16)
    }

    static func opacityAnimation(presented: Bool) -> Animation {
        presented ? .easeOut(duration: 0.15) : .easeIn(duration: 0.16)
    }
}

@MainActor
final class DelayedDismissal {
    typealias Schedule = (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

    private let schedule: Schedule
    private var generation = 0
    private(set) var isPending = false

    init(schedule: @escaping Schedule = { delay, action in
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            action()
        }
    }) {
        self.schedule = schedule
    }

    func start(after delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) {
        generation += 1
        let token = generation
        isPending = true
        schedule(delay) { [weak self] in
            guard let self, generation == token else {
                return
            }
            isPending = false
            action()
        }
    }

    func cancel() {
        generation += 1
        isPending = false
    }
}
```

- [ ] **Step 4: 确认通过**：`swift test --filter DelayedDismissalTests` → `Executed 3 tests, with 0 failures`。

- [ ] **Step 5: 提交**：`git add Sources/LaunchApp/PresentationTransition.swift Tests/LaunchAppTests/DelayedDismissalTests.swift && git commit -m "feat(界面): 可取消的延迟收起与动画参数"`

---

### Task 2: 模型与控制器的显示状态

**Files:**
- Modify: `Sources/LaunchApp/LauncherModel.swift`、`Sources/LaunchApp/LauncherController.swift`
- Test: `Tests/LaunchAppTests/LauncherControllerTests.swift`

- [ ] **Step 1: 失败测试**（`makeController` 之前）

```swift
    @MainActor
    func testPresentedStateFollowsShowAndHide() {
        let (controller, presenter) = makeController()
        XCTAssertFalse(controller.model.isPresented)

        controller.show()
        XCTAssertTrue(controller.model.isPresented)

        controller.hide(.escape)
        XCTAssertFalse(controller.model.isPresented)

        controller.show()
        XCTAssertTrue(controller.model.isPresented)
        XCTAssertEqual(presenter.presentCount, 2)
    }
```

- [ ] **Step 2: 确认失败**：编译错误，`LauncherModel` 没有 `isPresented`。

- [ ] **Step 3: 实现**

`LauncherModel`（`private(set) var marqueeRect: CGRect?` 之后）：

```swift
    private(set) var isPresented = false
```

`updateWallpaper` 之后：

```swift
    func setPresented(_ presented: Bool) {
        isPresented = presented
    }
```

`LauncherController.show()` 末尾 `presenter.present()` 之后加 `model.setPresented(true)`；`hide(_:)` 中 `presenter.dismiss(...)` 之前加 `model.setPresented(false)`。

- [ ] **Step 4: 确认通过**：全部测试无错误行。

- [ ] **Step 5: 提交**：`git commit -m "feat(界面): 模型记录启动器的显示状态"`（加上述两个源文件与测试文件）

---

### Task 3: 推迟收起与界面动画

**Files:**
- Modify: `Sources/LaunchApp/ScreenPresenter.swift`、`Sources/LaunchApp/LauncherView.swift`

- [ ] **Step 1: `ScreenPresenter`**

属性：`private let dismissal = DelayedDismissal()`。

`isVisible` 改为：

```swift
    // 隐藏动画进行中视为已关闭，此时再次唤起会从当前状态反向
    var isVisible: Bool {
        panel.isVisible && !dismissal.isPending
    }
```

`present()` 开头（`guard` 之前）加：

```swift
        dismissal.cancel()
        panel.ignoresMouseEvents = false
```

`dismiss(restoringPreviousApp:)` 改为：

```swift
    // 等隐藏动画播完再收起；立即切回之前的应用会把动画打断
    func dismiss(restoringPreviousApp: Bool) {
        panel.ignoresMouseEvents = true
        dismissal.start(after: PresentationTransition.hideDuration) { [weak self] in
            guard let self else {
                return
            }
            panel.orderOut(nil)
            panel.ignoresMouseEvents = false
            if restoringPreviousApp {
                NSApp.hide(nil)
            }
        }
    }
```

- [ ] **Step 2: `LauncherView`**

属性加 `@Environment(\.accessibilityReduceMotion) private var reduceMotion`。

背景：

```swift
                LauncherBackground(model: model, settings: settings)
                    .opacity(model.isPresented ? 1 : 0)
                    .animation(
                        PresentationTransition.backgroundAnimation(presented: model.isPresented),
                        value: model.isPresented
                    )
                    .ignoresSafeArea()
                    .onTapGesture(perform: onBackgroundClick)
```

内容层 `ZStack { homeContent ... FolderOverlay }` 的 `.coordinateSpace(.named(Self.contentSpace))` 之后加：

```swift
                .animation(PresentationTransition.scaleAnimation(presented: model.isPresented)) {
                    $0.scaleEffect(model.isPresented || reduceMotion ? 1 : PresentationTransition.hiddenScale)
                }
                .animation(PresentationTransition.opacityAnimation(presented: model.isPresented)) {
                    $0.opacity(model.isPresented ? 1 : 0)
                }
```

- [ ] **Step 3: 构建、测试、安装**，无警告、无失败。

- [ ] **Step 4: 提交**：`git commit -m "feat(界面): 唤起与隐藏动画"`

---

### Task 4: 验证与文档

- [ ] **Step 1: 回归 e2e**：备份布局与设置后依次运行第 4b、4c、5a 期 e2e，全部 `FAILURES 0`；结束后还原并核对。
- [ ] **Step 2: 计时**：用 `/tmp/launch-e2e-5a-dir/r/run` 确认唤起后面板立即出现、Esc 后约 0.22 秒收起。
- [ ] **Step 3: 文档**：`docs/manual-verification.md` 追加回归与计时结果；待验证追加「唤起与隐藏动画观感（请用户录屏，逐帧对比 LaunchOS）」。`git commit -m "chore(文档): 记录唤起与隐藏动画的验证结果"`

## Self-Review

- Spec 覆盖：3 交互规则 → Task 1（参数、延迟可取消）、2（状态）、3（推迟收起、反向、忽略鼠标、减弱动态效果、背景与内容动画）；5 测试 → Task 1/2 单测、Task 4 回归与计时。
- 类型一致：`PresentationTransition.hiddenScale/hideDuration/backgroundAnimation/scaleAnimation/opacityAnimation`、`DelayedDismissal(schedule:)/start(after:_:)/cancel()/isPending`、`LauncherModel.isPresented/setPresented(_:)` 各处一致。
