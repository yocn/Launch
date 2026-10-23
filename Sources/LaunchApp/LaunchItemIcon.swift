import SwiftUI
import LaunchCore

/// Shared entry point: only real applications are sent to the file-based icon resolver.
struct LaunchItemIcon: View {
    let item: LaunchItem
    let side: CGFloat

    var body: some View {
        if let application = item.application {
            AppIconImage(path: application.identity.path, side: side)
        } else {
            RoundedRectangle(cornerRadius: side * 0.225)
                .fill(Color.accentColor.opacity(0.8))
                .overlay {
                    Text(String(item.displayName.prefix(1)))
                        .font(.system(size: side * 0.5, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: side, height: side)
        }
    }
}
