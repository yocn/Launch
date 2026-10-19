import AppKit
import LaunchCore
import SwiftUI

struct LauncherView: View {
    let apps: [CatalogApp]
    let onClose: () -> Void
    let onLaunch: () -> Void

    @State private var query = ""
    @FocusState private var searchFieldIsFocused: Bool

    private var results: [CatalogApp] {
        SearchService.results(for: query, in: apps, hidden: [])
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 32) {
                TextField("搜索应用", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .frame(maxWidth: 420)
                    .focused($searchFieldIsFocused)

                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(minimum: 110), spacing: 30),
                            count: 7
                        ),
                        spacing: 32
                    ) {
                        ForEach(results, id: \.identity) { app in
                            Button {
                                if NSWorkspace.shared.open(
                                    URL(fileURLWithPath: app.identity.path)
                                ) {
                                    onLaunch()
                                }
                            } label: {
                                VStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(
                                        forFile: app.identity.path
                                    ))
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 72, height: 72)
                                    Text(app.displayName)
                                        .lineLimit(1)
                                        .frame(maxWidth: 120)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(app.displayName)
                        }
                    }
                    .padding(.horizontal, 72)
                    .padding(.bottom, 56)
                }
            }
            .padding(.top, 64)
        }
        .onExitCommand(perform: onClose)
        .onAppear {
            searchFieldIsFocused = true
        }
    }
}
