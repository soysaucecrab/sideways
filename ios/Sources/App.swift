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
                    switch phase {
                    case .active:
                        controller.applyDesiredFromControl()
                    case .background:
                        usage.flush()   // don't lose counts if suspended
                    default:
                        break
                    }
                }
        }
    }
}
