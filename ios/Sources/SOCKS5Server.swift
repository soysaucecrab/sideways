import Foundation
import Network

/// Minimal SOCKS5 proxy server (M1 scope: CONNECT + remote DNS, TCP only).
///
/// Listens on a local TCP port. `iproxy` on the Mac forwards a Mac-local port
/// over USB to this port, and macOS is configured to use it as its SOCKS proxy.
/// Each accepted connection is handled by a `SOCKS5Connection`, which performs
/// the SOCKS handshake and then relays bytes to an outbound connection opened
/// over the cellular interface.
final class SOCKS5Server {

    /// Aggregate, observable state for the UI.
    let stats: ProxyStats

    private let queue = DispatchQueue(label: "socks5.server", qos: .userInitiated)
    private var listener: NWListener?

    /// Live connections, keyed by an incrementing id so we can prune on close.
    private var connections: [Int: SOCKS5Connection] = [:]
    private var nextConnectionID = 0

    /// When true, outbound connections are pinned to the cellular interface.
    /// Disable for on-device debugging without a working USB tunnel.
    var requireCellular: Bool = true

    init(stats: ProxyStats) {
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
            DispatchQueue.main.async { [weak self] in
                self?.stats.setStopped(error: "listener_create_failed")
            }
            return
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async { self.stats.setRunning(port: port) }
            case .failed(let error):
                DispatchQueue.main.async { self.stats.setStopped(error: "\(error)") }
                self.stop()
            case .cancelled:
                DispatchQueue.main.async { self.stats.setStopped(error: nil) }
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
                self?.connections[finishedID] = nil
                DispatchQueue.main.async {
                    self?.stats.setActiveConnections(self?.connections.count ?? 0)
                }
            }
        }

        connections[id] = conn
        DispatchQueue.main.async { self.stats.setActiveConnections(self.connections.count) }
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
            DispatchQueue.main.async {
                self.stats.setActiveConnections(0)
                self.stats.setStopped(error: nil)
            }
        }
    }
}
