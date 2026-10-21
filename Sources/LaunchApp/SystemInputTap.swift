import AppKit
import ApplicationServices

// 接管 F4 键与触控板捏合需要辅助功能权限；未授权时每 2 秒检查一次，授权后自动开始
@MainActor
final class SystemInputTap {
    var f4Enabled = false {
        didSet {
            if oldValue != f4Enabled {
                refresh()
            }
        }
    }

    var pinch = PinchGesture.off {
        didSet {
            recognizer.gesture = pinch
            if oldValue != pinch {
                refresh()
            }
        }
    }

    // 按住 fn 或开启标准功能键时的 F4、旧键盘的启动台键、新键盘 F4 位置的 Spotlight 键（待按键核对）
    static let f4KeyCodes: Set<Int64> = [118, 131, 177]
    // 只记录 F1～F12 与系统功能键的键码，不记录字母、数字等普通按键
    private static let functionKeyCodes: Set<Int64> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
    private static let systemDefinedType: UInt32 = 14
    private static let gestureType: UInt32 = 29

    private let onTrigger: () -> Void
    private var recognizer = PinchRecognizer()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var swallowsGesture = false

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    // 由用户点击触发：系统弹出授权提示，并把 Launch 加进辅助功能列表
    static func requestPermission() {
        // 即 kAXTrustedCheckOptionPrompt；那个常量是全局变量，Swift 6 不允许直接引用
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private func refresh() {
        stopTap()
        guard f4Enabled || pinch != .off else {
            stopPolling()
            return
        }
        guard Self.isTrusted else {
            startPolling()
            return
        }
        stopPolling()
        startTap()
    }

    private func startPolling() {
        guard permissionTimer == nil else {
            return
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Self.isTrusted else {
                    return
                }
                AppLog.shared.info("已获得辅助功能权限，开始接管 F4 键与触控板手势")
                self.refresh()
            }
        }
    }

    private func stopPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func startTap() {
        var mask: CGEventMask = 0
        if f4Enabled {
            mask |= 1 << CGEventType.keyDown.rawValue
            mask |= 1 << Self.systemDefinedType
        }
        if pinch != .off {
            mask |= 1 << Self.gestureType
        }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else {
                return Unmanaged.passUnretained(event)
            }
            let tap = Unmanaged<SystemInputTap>.fromOpaque(info).takeUnretainedValue()
            nonisolated(unsafe) let event = event
            let swallows = MainActor.assumeIsolated {
                tap.swallows(type, event)
            }
            return swallows ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            AppLog.shared.error("创建事件拦截失败")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        self.source = source
    }

    private func stopTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        recognizer.end()
        swallowsGesture = false
    }

    private func swallows(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 回调太慢或系统暂停时拦截会被停用，需要重新打开
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        case .keyDown:
            return handleKey(event)
        default:
            if type.rawValue == Self.systemDefinedType {
                logSystemKey(event)
            } else if type.rawValue == Self.gestureType {
                return handleGesture(event)
            }
            return false
        }
    }

    private func handleKey(_ event: CGEvent) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if Self.functionKeyCodes.contains(code) || code >= 128 {
            AppLog.shared.info("特殊键 keyCode=\(code)")
        }
        let modifiers = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        guard f4Enabled, Self.f4KeyCodes.contains(code), modifiers.isEmpty else {
            return false
        }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            onTrigger()
        }
        return true
    }

    // 媒体键等走系统功能键事件，先只记录，核对 F4 是否走这条路
    private func logSystemKey(_ event: CGEvent) {
        guard let system = NSEvent(cgEvent: event), system.subtype.rawValue == 8 else {
            return
        }
        let code = (system.data1 & 0xFFFF_0000) >> 16
        if (system.data1 & 0xFF00) >> 8 == 0x0A {
            AppLog.shared.info("系统功能键 code=\(code)")
        }
    }

    // 识别出捏合后同一次手势的后续事件都拦下，尽量不让系统再执行它的捏合
    private func handleGesture(_ event: CGEvent) -> Bool {
        guard let gesture = NSEvent(cgEvent: event) else {
            return false
        }
        let active = gesture.allTouches().filter { $0.phase != .ended && $0.phase != .cancelled }
        guard !active.isEmpty else {
            recognizer.end()
            defer { swallowsGesture = false }
            return swallowsGesture
        }
        if recognizer.update(touches: active.map(\.normalizedPosition)) {
            AppLog.shared.info("识别到 \(active.count) 指捏合")
            swallowsGesture = true
            onTrigger()
        }
        return swallowsGesture
    }
}
