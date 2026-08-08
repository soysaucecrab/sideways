import SwiftUI

@main
struct DataSharingApp: App {
    @StateObject private var stats: ProxyStats
    @StateObject private var controller: ProxyController

    init() {
        let stats = ProxyStats()
        _stats = StateObject(wrappedValue: stats)
        _controller = StateObject(wrappedValue: ProxyController(stats: stats))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .environmentObject(stats)
        }
    }
}
