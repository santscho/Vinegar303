import SwiftUI

@main
struct Vinegar303App: App {
    @StateObject private var host = Vinegar303Host()

    var body: some Scene {
        WindowGroup("Vinegar303") {
            Vinegar303HostView(host: host)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: Vinegar303WindowMetrics.nativeWidth,
            height: Vinegar303WindowMetrics.initialContentHeight
        )
    }
}
