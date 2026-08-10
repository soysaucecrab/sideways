import Foundation
import Combine
import UIKit

/// Bridges the SwiftUI layer and the `SOCKS5Server`, and keeps the screen awake
/// while running (spec §7: v1 is foreground-only, so we prevent auto-lock to
/// keep the app from being suspended mid-session).
final class ProxyController: ObservableObject {
    let stats: ProxyStats
    @Published var requireCellular: Bool = true

    private let server: SOCKS5Server

    init(stats: ProxyStats) {
        self.stats = stats
        self.server = SOCKS5Server(stats: stats)
        self.requireCellular = SharedState.requireCellular
    }

    func start(port: UInt16) {
        server.requireCellular = requireCellular
        server.start(port: port)
        UIApplication.shared.isIdleTimerDisabled = true
        SharedState.port = port
        SharedState.requireCellular = requireCellular
    }

    func stop() {
        server.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Applies a pending start/stop request written by the Control Center
    /// toggle. Called when the scene becomes active — the toggle opens the app,
    /// so activation is the earliest point the listener can safely run.
    func applyDesiredFromControl() {
        guard let desired = SharedState.takeDesired() else { return }
        if desired, !stats.isRunning {
            start(port: SharedState.port)
        } else if !desired, stats.isRunning {
            stop()
        }
    }
}
