import Foundation

/// Proxy counters inside the packet tunnel extension. Mutated from the SOCKS
/// server queue on every relayed chunk, so updates are a lock and an add —
/// no main-thread hop (the extension has no UI, and per-chunk wakeups cost
/// CPU and heat on a phone that relays traffic for hours).
final class TunnelStats {
    private let lock = NSLock()
    private var state = TunnelSnapshot()

    func setRunning(port: UInt16) {
        withLock {
            state.isRunning = true
            state.port = port
            state.lastError = nil
        }
    }

    func setStopped(error: String?) {
        withLock {
            state.isRunning = false
            if let error { state.lastError = error }
        }
    }

    func setActiveConnections(_ count: Int) {
        withLock { state.activeConnections = max(0, count) }
    }

    func addBytesIn(_ n: Int) {
        withLock { state.bytesIn += n }
    }

    func addBytesOut(_ n: Int) {
        withLock { state.bytesOut += n }
    }

    func setRates(in rIn: Int, out rOut: Int) {
        withLock {
            state.rateIn = max(0, rIn)
            state.rateOut = max(0, rOut)
        }
    }

    func snapshot() -> TunnelSnapshot {
        withLock { state }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
