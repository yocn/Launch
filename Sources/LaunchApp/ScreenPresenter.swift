import AppKit
import CoreGraphics
import LaunchCore
import SwiftUI

public enum ScreenSelectionPolicy {
    public static func screenIndex(
        containing point: CGPoint,
        in screenFrames: [CGRect]
    ) -> Int? {
        screenFrames.firstIndex(where: { $0.contains(point) })
    }
}

public enum LauncherPanelConfiguration {
    public static let styleMask: NSWindow.StyleMask = [.borderless]
}

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class ScreenPresenter {
    private var panel: NSPanel?

    func show(catalog: [CatalogApp]) {
        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        let screenIndex = ScreenSelectionPolicy.screenIndex(
            containing: NSEvent.mouseLocation,
            in: frames
        ) ?? 0
        guard screens.indices.contains(screenIndex) else {
            return
        }

        let targetScreen = screens[screenIndex]
        let panel = launcherPanel(for: targetScreen)
        panel.contentView = NSHostingView(
            rootView: LauncherView(
                apps: catalog,
                onClose: { [weak self] in self?.hide() },
                onLaunch: { [weak self] in self?.hide() }
            )
        )
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func launcherPanel(for screen: NSScreen) -> NSPanel {
        let panel = LauncherPanel(
            contentRect: screen.frame,
            styleMask: LauncherPanelConfiguration.styleMask,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        return panel
    }
}
