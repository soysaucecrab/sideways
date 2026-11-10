import SwiftUI

@main
struct DataSharingApp: App {
    @StateObject private var stats: ProxyStats
    @StateObject private var usage: UsageStore
    @StateObject private var controller: ProxyController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let stats = ProxyStats()
        let usage = UsageStore()
        _stats = StateObject(wrappedValue: stats)
        _usage = StateObject(wrappedValue: usage)
        _controller = StateObject(wrappedValue: ProxyController(stats: stats, usage: usage))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .environmentObject(stats)
                .environmentObject(usage)
                .onChange(of: scenePhase) { _, phase in
                    // The tunnel keeps running while the app is closed, so
                    // re-sync with it on every return to the foreground.
                    if phase == .active {
                        controller.refresh()
                        controller.applyDesiredFromControl()
                    }
                }
        }
    }
}
