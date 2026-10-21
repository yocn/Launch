import AppKit
import SwiftUI

// 系统材质会在模糊之上再叠一层白色或灰色蒙层，这里只保留模糊与饱和度；参数按 LaunchOS 录屏拟合
enum BackdropBlur {
    static let radius = 30.0
    static let saturation = 1.6

    // CABackdropLayer 与 CAFilter 是私有类，取不到时返回空，由调用方退回系统材质
    static func makeLayer() -> CALayer? {
        guard let layerClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let saturate = filter("colorSaturate"),
              let blur = filter("gaussianBlur") else {
            return nil
        }
        saturate.setValue(saturation, forKey: "inputAmount")
        blur.setValue(radius, forKey: "inputRadius")
        blur.setValue(true, forKey: "inputNormalizeEdges")
        let layer = layerClass.init()
        guard layer.responds(to: NSSelectorFromString("setWindowServerAware:")),
              layer.responds(to: NSSelectorFromString("setScale:")) else {
            return nil
        }
        layer.setValue(true, forKey: "windowServerAware")
        // 与系统材质相同的降采样，全屏模糊的开销不变
        layer.setValue(0.25, forKey: "scale")
        layer.filters = [saturate, blur]
        return layer
    }

    static let isAvailable = makeLayer() != nil

    private static func filter(_ type: String) -> NSObject? {
        let selector = NSSelectorFromString("filterWithType:")
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
              filterClass.responds(to: selector) else {
            return nil
        }
        return filterClass.perform(selector, with: type)?.takeUnretainedValue() as? NSObject
    }
}

struct BackdropBlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> BackdropBlurNSView {
        BackdropBlurNSView(frame: .zero)
    }

    func updateNSView(_ nsView: BackdropBlurNSView, context: Context) {}
}

final class BackdropBlurNSView: NSView {
    private let backdrop = BackdropBlur.makeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        if let backdrop {
            layer?.addSublayer(backdrop)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop?.frame = bounds
        CATransaction.commit()
    }
}
