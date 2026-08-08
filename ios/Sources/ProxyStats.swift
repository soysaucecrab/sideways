import Foundation
import Combine

/// Observable state for the proxy UI (spec §5.1: active-connection count,
/// bytes in/out, listen port, running state).
///
/// The server calls these mutators from its own serial queue; each one hops to
/// the main thread itself, so callers never have to. `@Published` mutations
/// therefore always land on main, as SwiftUI requires.
final class ProxyStats: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var listenPort: UInt16 = 8888
    @Published private(set) var activeConnections = 0
    @Published private(set) var bytesIn: Int = 0    // internet → Mac
    @Published private(set) var bytesOut: Int = 0    // Mac → internet
    @Published private(set) var lastError: String?

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func setRunning(port: UInt16) {
        onMain {
            self.isRunning = true
            self.listenPort = port
            self.lastError = nil
        }
    }

    func setStopped(error: String?) {
        onMain {
            self.isRunning = false
            if let error { self.lastError = error }
        }
    }

    func setActiveConnections(_ count: Int) {
        onMain { self.activeConnections = max(0, count) }
    }

    func addBytesIn(_ n: Int) {
        onMain { self.bytesIn += n }
    }

    func addBytesOut(_ n: Int) {
        onMain { self.bytesOut += n }
    }

    func resetCounters() {
        onMain {
            self.bytesIn = 0
            self.bytesOut = 0
        }
    }

    var bytesInText: String { ByteFormat.string(bytesIn) }
    var bytesOutText: String { ByteFormat.string(bytesOut) }
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
}
