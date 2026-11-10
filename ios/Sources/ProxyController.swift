import Foundation
import Combine
import NetworkExtension

/// Bridges the SwiftUI layer and the packet tunnel extension that hosts the
/// SOCKS5 server.
///
/// Starting the proxy means saving and starting a VPN configuration whose
/// provider is that extension. The extension keeps the server alive while the
/// app is backgrounded or the screen is locked, so the screen no longer has to
/// stay on. While the app is open and the tunnel is connected, a timer polls
/// the extension every `pollInterval` seconds for live stats; usage totals are
/// recorded by the extension itself and only re-read here.
final class ProxyController: ObservableObject {
    let stats: ProxyStats
    let usage: UsageStore
    @Published var requireCellular: Bool

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var pollTimer: Timer?

    /// Stats polling period in seconds while the app is open.
    private let pollInterval: TimeInterval = 3.0

    init(stats: ProxyStats, usage: UsageStore) {
        self.stats = stats
        self.usage = usage
        self.requireCellular = SharedState.requireCellular
        refresh()
    }

    deinit {
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
    }

    // MARK: - Start / stop

    func start(port: UInt16) {
        SharedState.port = port
        SharedState.requireCellular = requireCellular
        stats.resetCounters()

        loadManager { [weak self] existing in
            guard let self else { return }
            let manager = existing ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = SharedState.tunnelBundleID
            proto.serverAddress = "USB 127.0.0.1:\(port)"
            proto.providerConfiguration = [
                "port": Int(port),
                "requireCellular": self.requireCellular,
            ]
            manager.protocolConfiguration = proto
            manager.localizedDescription = "Data Sharing"
            manager.isEnabled = true

            // The first save shows the system "Add VPN Configurations" prompt.
            manager.saveToPreferences { error in
                if let error { self.fail(error); return }
                // Starting right after a save fails with a stale-configuration
                // error unless the configuration is reloaded first.
                manager.loadFromPreferences { error in
                    if let error { self.fail(error); return }
                    self.attach(manager)
                    do {
                        try manager.connection.startVPNTunnel()
                    } catch {
                        self.fail(error)
                    }
                }
            }
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    /// Applies a pending start/stop request written by the Control Center
    /// toggle. Called when the scene becomes active — the toggle opens the app,
    /// the process allowed to manage the VPN configuration. Decides from the
    /// live VPN status rather than `stats`, which may not have synced yet.
    func applyDesiredFromControl() {
        guard let desired = SharedState.takeDesired() else { return }
        loadManager { [weak self] manager in
            guard let self else { return }
            let status = manager?.connection.status ?? .invalid
            let running = [.connected, .connecting, .reasserting].contains(status)
            if desired, !running {
                self.start(port: SharedState.port)
            } else if !desired, running {
                manager?.connection.stopVPNTunnel()
            }
        }
    }

    /// Re-syncs with the system VPN state, e.g. after the tunnel was toggled in
    /// Settings or kept running while the app was closed.
    func refresh() {
        loadManager(completion: nil)
        usage.reload()
    }

    // MARK: - VPN configuration

    private func loadManager(completion: ((NETunnelProviderManager?) -> Void)?) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error { self.fail(error) }
                let match = managers?.first {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                        .providerBundleIdentifier == SharedState.tunnelBundleID
                }
                if let match { self.attach(match) }
                completion?(match)
            }
        }
    }

    private func attach(_ manager: NETunnelProviderManager) {
        if self.manager !== manager {
            self.manager = manager
            if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
            statusObserver = NotificationCenter.default.addObserver(
                forName: .NEVPNStatusDidChange,
                object: manager.connection,
                queue: .main
            ) { [weak self] _ in self?.statusChanged() }
        }
        statusChanged()
    }

    private func statusChanged() {
        guard let connection = manager?.connection else { return }
        switch connection.status {
        case .connected:
            stats.setRunning(port: SharedState.port)
            startPolling()
        case .disconnected, .invalid:
            stopPolling()
            stats.setStopped(error: nil)
            usage.reload()
            // Surface why the tunnel went down (e.g. the port was in use).
            connection.fetchLastDisconnectError { [weak self] error in
                if let error { self?.stats.setStopped(error: error.localizedDescription) }
            }
        default:
            break   // connecting / disconnecting / reasserting are transient
        }
    }

    private func fail(_ error: Error) {
        stats.setStopped(error: error.localizedDescription)
    }

    // MARK: - Stats polling

    private func startPolling() {
        guard pollTimer == nil else { return }
        poll()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // .common so polling keeps firing while the user scrolls the UI.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        stats.clearRates()
    }

    private func poll() {
        guard let session = manager?.connection as? NETunnelProviderSession,
              session.status == .connected else { return }
        try? session.sendProviderMessage(Data()) { [weak self] data in
            guard let data,
                  let snapshot = try? JSONDecoder().decode(TunnelSnapshot.self, from: data) else { return }
            self?.stats.apply(snapshot)
            DispatchQueue.main.async { self?.usage.reload() }
        }
    }
}
