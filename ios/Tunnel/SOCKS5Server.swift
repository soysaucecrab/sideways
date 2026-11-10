import Foundation
import Network

/// Minimal SOCKS5 proxy server (M1 scope: CONNECT + remote DNS, TCP only).
///
/// Hosted by `PacketTunnelProvider`, so it keeps running while the app is in
/// the background or the screen is off. Listens on a local TCP port; `iproxy`
/// on the Mac forwards a Mac-local port over USB to it. Each accepted
/// connection is handled by a `SOCKS5Connection`, which performs the SOCKS
/// handshake and then relays bytes to an outbound connection opened over the
/// cellular interface.
final class SOCKS5Server {

    enum ListenerEvent {
        case ready
        case failed(Error)
    }

    /// Thread-safe counters, read by the tunnel provider for app snapshots.
    let stats: TunnelStats

    /// Listener readiness/failure. The tunnel provider waits for `.ready`
    /// before reporting the tunnel as connected, so the VPN never shows "on"
    /// while the port is not actually bound. Called on `queue`.
    var stateHandler: ((ListenerEvent) -> Void)?

    private let queue = DispatchQueue(label: "socks5.server", qos: .userInitiated)
    private var listener: NWListener?

    /// Live connections, keyed by an incrementing id so we can prune on close.
    private var connections: [Int: SOCKS5Connection] = [:]
    private var nextConnectionID = 0

    /// When true, outbound connections are pinned to the cellular interface.
    /// Disable for on-device debugging without a working USB tunnel.
    var requireCellular: Bool = true

    init(stats: TunnelStats) {
        self.stats = stats
    }

    /// Start listening on `127.0.0.1:port`. Idempotent-ish: call `stop()` first.
    func start(port: UInt16) {
        queue.async { [weak self] in
            self?.startLocked(port: port)
        }
    }

    private func startLocked(port: UInt16) {
        guard listener == nil else { return }

        let params = NWParameters.tcp
        // Bind explicitly to loopback: the tunnel terminates the USB link on the
        // phone, so we never want to be reachable over Wi-Fi/cellular directly.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port) ?? 8888
        )
        params.allowLocalEndpointReuse = true

        // The bind port is carried by `requiredLocalEndpoint` above; passing it
        // again via `on:` is contradictory and makes the initializer fail.
        guard let listener = try? NWListener(using: params) else {
            stats.setStopped(error: "listener_create_failed")
            stateHandler?(.failed(NSError(
                domain: "DataSharing", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "listener_create_failed"]
            )))
            return
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.stats.setRunning(port: port)
                self.stateHandler?(.ready)
            case .failed(let error):
                self.stats.setStopped(error: "\(error)")
                self.stateHandler?(.failed(error))
                self.stop()
            case .cancelled:
                self.stats.setStopped(error: nil)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] nwConnection in
            self?.accept(nwConnection)
        }

        self.listener = listener
        listener.start(queue: queue)
    }

    private func accept(_ nwConnection: NWConnection) {
        let id = nextConnectionID
        nextConnectionID += 1

        let conn = SOCKS5Connection(
            id: id,
            inbound: nwConnection,
            queue: queue,
            requireCellular: requireCellular,
            stats: stats
        ) { [weak self] finishedID in
            self?.queue.async {
                guard let self else { return }
                self.connections[finishedID] = nil
                self.stats.setActiveConnections(self.connections.count)
            }
        }

        connections[id] = conn
        stats.setActiveConnections(connections.count)
        conn.start()
    }

    /// Stop the listener and tear down all live connections.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            for (_, conn) in self.connections {
                conn.cancel()
            }
            self.connections.removeAll()
            self.stats.setActiveConnections(0)
            self.stats.setStopped(error: nil)
        }
    }
}
