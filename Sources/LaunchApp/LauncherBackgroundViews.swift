import AppKit
import LaunchCore
import SwiftUI

// 启动器背景：画布位置、模糊背景、壁纸、边缘渐隐与窗口模式的边框
// 整块屏幕在本窗口里的位置；显示程序坞时启动器和程序坞那一条分属两个窗口，壁纸据此对齐
@MainActor
@Observable
final class BackgroundCanvas {
    var screenFrame: CGRect?
    // 显示程序坞时启动器背景在这条边上渐隐，透出垫在下面的那一条
    var fadeEdge: Edge?
}

// 程序坞那一条的背景，垫在程序坞下面，与启动器的背景和淡入淡出一致
struct DockStripView: View {
    let model: LauncherModel
    let settings: LauncherSettings
    let onTap: () -> Void

    var body: some View {
        LauncherBackground(model: model, settings: settings)
            .opacity(model.isPresented ? 1 : 0)
            .animation(PresentationTransition.backgroundAnimation(presented: model.isPresented), value: model.isPresented)
            .ignoresSafeArea()
            .onTapGesture(perform: onTap)
    }
}

struct LauncherBackground: View {
    let model: LauncherModel
    let settings: LauncherSettings
    @Environment(BackgroundCanvas.self) private var canvas: BackgroundCanvas?

    var body: some View {
        ZStack {
            if settings.background != .glass, let wallpaper = model.wallpaper {
                WallpaperImage(wallpaper: wallpaper, canvas: canvas?.screenFrame)
            } else if BackdropBlur.isAvailable {
                BackdropBlurView()
            } else {
                Rectangle()
                    .fill(.regularMaterial)
            }
            // 压暗用深灰不用纯黑，按 LaunchOS 录屏拟合
            Color(white: 0.12).opacity(settings.dimming)
        }
        .mask {
            if let edge = canvas?.fadeEdge {
                EdgeFade(edge: edge, length: DockStrip.blendLength)
            } else {
                Rectangle()
            }
        }
        .contentShape(Rectangle())
    }
}

struct EdgeFade: View {
    let edge: Edge
    let length: CGFloat

    var body: some View {
        switch edge {
        case .leading:
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: length)
                Rectangle()
            }
        case .trailing:
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: length)
            }
        case .top:
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: length)
                Rectangle()
            }
        case .bottom:
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: length)
            }
        }
    }
}

struct WallpaperImage: View {
    let wallpaper: Wallpaper
    let canvas: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let rect = canvas ?? CGRect(origin: .zero, size: proxy.size)
            ZStack {
                Color(nsColor: wallpaper.fillColor ?? .black)
                switch wallpaper.fill {
                case .aspectFill:
                    image.aspectRatio(contentMode: .fill)
                case .aspectFit:
                    image.aspectRatio(contentMode: .fit)
                case .stretch:
                    image
                case .center:
                    Image(nsImage: wallpaper.image)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .clipped()
            .offset(x: rect.minX, y: rect.minY)
        }
        .clipped()
    }

    private var image: some View {
        Image(nsImage: wallpaper.image)
            .resizable()
            .interpolation(.high)
    }
}

// 窗口模式：背景只留中间的圆角区域，加一圈淡边与柔和投影
struct WindowFrame: ViewModifier {
    let size: CGSize?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if let size {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .mask {
                    shape.frame(width: size.width, height: size.height)
                }
                .overlay {
                    shape
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        .frame(width: size.width, height: size.height)
                }
                .background {
                    shape
                        .fill(.black.opacity(0.3))
                        .frame(width: size.width, height: size.height)
                        .blur(radius: 24)
                        .offset(y: 10)
                }
        } else {
            content
        }
    }
}

// 只有这一层读取提示文字
