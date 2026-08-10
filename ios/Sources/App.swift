import SwiftUI

@main
struct DataSharingApp: App {
    @StateObject private var stats: ProxyStats
    @StateObject private var controller: ProxyController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let stats = ProxyStats()
        _stats = StateObject(wrappedValue: stats)
        _controller = StateObject(wrappedValue: ProxyController(stats: stats))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .environmentObject(stats)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        controller.applyDesiredFromControl()
                    }
                }
        }
    }
}
