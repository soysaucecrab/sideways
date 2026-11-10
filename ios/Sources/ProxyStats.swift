import Foundation
import Combine
import WidgetKit

/// Observable state for the proxy UI (spec §5.1: active-connection count,
/// bytes in/out, listen port, running state).
///
/// The proxy runs in the packet tunnel extension, so this is a mirror: the
/// controller sets the running state from the VPN status and applies
/// snapshots polled from the extension. Each mutator hops to the main thread
/// itself, so `@Published` mutations always land on main, as SwiftUI requires.
final class ProxyStats: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var listenPort: UInt16 = 8888
    @Published private(set) var activeConnections = 0
    @Published private(set) var bytesIn: Int = 0    // internet → Mac
    @Published private(set) var bytesOut: Int = 0    // Mac → internet
    @Published private(set) var rateIn: Int = 0     // bytes/sec, internet → Mac
    @Published private(set) var rateOut: Int = 0    // bytes/sec, Mac → internet
    @Published private(set) var lastError: String?

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func setRunning(port: UInt16) {
        onMain {
            self.isRunning = true
            self.listenPort = port
            self.lastError = nil
            Self.syncControl(running: true)
        }
    }

    func setStopped(error: String?) {
        onMain {
            self.isRunning = false
            if let error { self.lastError = error }
            Self.syncControl(running: false)
        }
    }

    /// Mirrors the running state into the app group and refreshes the
    /// Control Center toggle (iOS 18+) so it never shows a stale state.
    private static func syncControl(running: Bool) {
        SharedState.isRunning = running
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: SharedState.controlKind)
        }
    }

    /// Applies counters polled from the tunnel extension.
    func apply(_ snapshot: TunnelSnapshot) {
        onMain {
            self.activeConnections = snapshot.activeConnections
            self.bytesIn = snapshot.bytesIn
            self.bytesOut = snapshot.bytesOut
            self.rateIn = snapshot.rateIn
            self.rateOut = snapshot.rateOut
            if let error = snapshot.lastError { self.lastError = error }
        }
    }

    /// Zeroes the live rates when the tunnel stops; session totals stay visible.
    func clearRates() {
        onMain {
            self.rateIn = 0
            self.rateOut = 0
        }
    }

    func resetCounters() {
        onMain {
            self.bytesIn = 0
            self.bytesOut = 0
            self.rateIn = 0
            self.rateOut = 0
        }
    }

    var bytesInText: String { ByteFormat.string(bytesIn) }
    var bytesOutText: String { ByteFormat.string(bytesOut) }
    var rateInText: String { ByteFormat.rate(rateIn) }
    var rateOutText: String { ByteFormat.rate(rateOut) }
}

enum ByteFormat {
    static func string(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var idx = 0
        while value >= 1024 && idx < units.count - 1 {
            value /= 1024
            idx += 1
        }
        return idx == 0 ? "\(bytes) B" : String(format: "%.1f %@", value, units[idx])
    }

    static func rate(_ bytesPerSec: Int) -> String {
        string(bytesPerSec) + "/s"
    }
}
