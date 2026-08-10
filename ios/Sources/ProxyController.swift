import Foundation
import Combine
import UIKit

/// Bridges the SwiftUI layer and the `SOCKS5Server`, and keeps the screen awake
/// while running (spec §7: v1 is foreground-only, so we prevent auto-lock to
/// keep the app from being suspended mid-session).
///
/// While running, a 1 Hz timer samples the session byte counters to derive the
/// current up/down rate and to feed the persistent `UsageStore`.
final class ProxyController: ObservableObject {
    let stats: ProxyStats
    let usage: UsageStore
    @Published var requireCellular: Bool

    private let server: SOCKS5Server
    private var sampleTimer: Timer?
    private var lastIn = 0
    private var lastOut = 0
    private var tick = 0

    init(stats: ProxyStats, usage: UsageStore) {
        self.stats = stats
        self.usage = usage
        self.server = SOCKS5Server(stats: stats)
        self.requireCellular = SharedState.requireCellular
    }

    func start(port: UInt16) {
        stats.resetCounters()
        server.requireCellular = requireCellular
        server.start(port: port)
        UIApplication.shared.isIdleTimerDisabled = true
        SharedState.port = port
        SharedState.requireCellular = requireCellular
        startSampling()
    }

    func stop() {
        stopSampling()
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

    // MARK: - Rate sampling

    private func startSampling() {
        lastIn = stats.bytesIn
        lastOut = stats.bytesOut
        tick = 0
        sampleTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
        // .common so sampling keeps firing while the user scrolls the UI.
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
    }

    private func stopSampling() {
        sampleTimer?.invalidate()
        sampleTimer = nil
        stats.setRates(in: 0, out: 0)
        usage.flush()
    }

    private func sample() {
        let curIn = stats.bytesIn
        let curOut = stats.bytesOut
        let dIn = max(0, curIn - lastIn)
        let dOut = max(0, curOut - lastOut)
        lastIn = curIn
        lastOut = curOut

        stats.setRates(in: dIn, out: dOut)   // 1 s interval => bytes/sec
        usage.add(inBytes: dIn, outBytes: dOut)

        tick += 1
        if tick % 5 == 0 { usage.flush() }   // persist periodically
    }
}
