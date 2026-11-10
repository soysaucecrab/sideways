import Foundation
import NetworkExtension
import os
import WidgetKit

/// Hosts the SOCKS5 server inside a packet tunnel extension.
///
/// iOS suspends a backgrounded app within seconds, which used to stop the
/// proxy unless the screen was kept on. A packet tunnel provider instead stays
/// alive for as long as the VPN is connected, so the server keeps relaying
/// with the app closed and the screen locked.
///
/// The tunnel itself carries no traffic: it routes nothing, so the phone's
/// own connections keep their normal path. It exists only to keep this
/// process — and the loopback listener that `iproxy` reaches over USB — alive.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private static let log = Logger(subsystem: "com.zinu.datasharing.ios.tunnel", category: "tunnel")

    private let stats = TunnelStats()
    private var server: SOCKS5Server?

    // Rate + usage sampling; `usage` and the counters below are only touched
    // on `samplerQueue`.
    private let samplerQueue = DispatchQueue(label: "tunnel.sampler", qos: .utility)
    private var sampleTimer: DispatchSourceTimer?
    private var usage: UsageStore?
    private var lastIn = 0
    private var lastOut = 0
    private var tick = 0

    /// Sampling period in seconds. Slow on purpose: fewer wakeups mean less
    /// heat and battery drain on a phone that relays traffic for hours.
    private let sampleInterval: TimeInterval = 3.0

    // MARK: - Lifecycle

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let port = (config["port"] as? Int).flatMap { UInt16(exactly: $0) } ?? SharedState.port
        let requireCellular = config["requireCellular"] as? Bool ?? SharedState.requireCellular

        // Route nothing into the tunnel (empty includedRoutes, no DNS
        // settings): the phone's own traffic must stay on its normal path.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = []
        settings.ipv4Settings = ipv4

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            if let error {
                Self.log.error("network settings failed: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
                return
            }
            self.startServer(port: port, requireCellular: requireCellular, completionHandler: completionHandler)
        }
    }

    private func startServer(port: UInt16, requireCellular: Bool,
                             completionHandler: @escaping (Error?) -> Void) {
        let server = SOCKS5Server(stats: stats)
        server.requireCellular = requireCellular

        // Report the tunnel as up only once the port is bound. Events arrive
        // on the server's serial queue, so `started` needs no lock.
        var started = false
        server.stateHandler = { [weak self] event in
            guard let self else { return }
            switch event {
            case .ready where !started:
                started = true
                Self.log.info("listening on 127.0.0.1:\(port), cellular=\(requireCellular)")
                self.startSampling()
                Self.publishRunning(true)
                completionHandler(nil)
            case .failed(let error) where !started:
                started = true
                Self.log.error("listener failed to start: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
            case .failed(let error):
                Self.log.error("listener failed: \(error.localizedDescription, privacy: .public)")
                self.cancelTunnelWithError(error)
            default:
                break
            }
        }

        self.server = server
        server.start(port: port)
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        Self.log.info("stopping, reason=\(reason.rawValue)")
        stopSampling()
        server?.stop()
        server = nil
        Self.publishRunning(false)
        completionHandler()
    }

    /// The app polls this while it is open to drive its live stats UI.
    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        completionHandler?(try? JSONEncoder().encode(stats.snapshot()))
    }

    // MARK: - Sampling

    private func startSampling() {
        samplerQueue.async { [weak self] in
            guard let self else { return }
            self.usage = UsageStore()
            let now = self.stats.snapshot()
            self.lastIn = now.bytesIn
            self.lastOut = now.bytesOut
            self.tick = 0

            let timer = DispatchSource.makeTimerSource(queue: self.samplerQueue)
            // Leeway lets iOS coalesce this with other wakeups.
            timer.schedule(deadline: .now() + self.sampleInterval,
                           repeating: self.sampleInterval,
                           leeway: .seconds(1))
            timer.setEventHandler { [weak self] in self?.sample() }
            timer.resume()
            self.sampleTimer = timer
        }
    }

    private func stopSampling() {
        // Synchronous so the final usage flush lands before the process exits.
        samplerQueue.sync {
            sampleTimer?.cancel()
            sampleTimer = nil
            sample()
            usage?.flush()
            usage = nil
            stats.setRates(in: 0, out: 0)
        }
    }

    private func sample() {
        guard let usage else { return }
        let now = stats.snapshot()
        let dIn = max(0, now.bytesIn - lastIn)
        let dOut = max(0, now.bytesOut - lastOut)
        lastIn = now.bytesIn
        lastOut = now.bytesOut

        // Deltas span `sampleInterval` seconds; normalize to bytes/sec.
        stats.setRates(in: Int(Double(dIn) / sampleInterval),
                       out: Int(Double(dOut) / sampleInterval))
        usage.add(inBytes: dIn, outBytes: dOut)

        tick += 1
        if tick % 5 == 0 { usage.flush() }   // persist periodically
    }

    // MARK: - Control Center sync

    /// Mirrors the running state into the app group and refreshes the Control
    /// Center toggle, so it is correct even when the app is not running.
    private static func publishRunning(_ running: Bool) {
        SharedState.isRunning = running
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: SharedState.controlKind)
        }
    }
}
