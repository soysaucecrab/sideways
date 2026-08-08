import SwiftUI

@main
struct DataSharingMacApp: App {
    @StateObject private var tunnel = TunnelManager()

    var body: some Scene {
        MenuBarExtra("Data Sharing", systemImage: menuIcon) {
            MenuContentView(tunnel: tunnel)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuIcon: String {
        switch tunnel.status {
        case .running: return "antenna.radiowaves.left.and.right"
        case .failed: return "exclamationmark.triangle"
        case .idle: return "antenna.radiowaves.left.and.right.slash"
        }
    }
}
