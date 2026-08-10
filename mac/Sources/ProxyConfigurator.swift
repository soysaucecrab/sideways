import Foundation

/// Human-readable failure from a `networksetup` mutation, carried in `Result`.
struct ProxyError: Error {
    let message: String
}

/// Reads and writes the macOS system SOCKS proxy via `networksetup`
/// (spec §5.3). Operates on one network service (e.g. "Wi-Fi").
///
/// Note: `networksetup` mutations require the calling user to be an admin.
/// If a write is refused, `setSOCKS`/`disableSOCKS` surface the stderr text so
/// the UI can explain it rather than failing silently.
enum ProxyConfigurator {
    static let networksetup = "/usr/sbin/networksetup"

    /// All configurable network services, best-guess primary first.
    /// Disabled services (prefixed with `*`) are omitted.
    static func networkServices() -> [String] {
        let result = Shell.run(networksetup, ["-listallnetworkservices"])
        guard result.ok else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") && !$0.contains("denotes that") }
    }

    struct SOCKSState {
        let enabled: Bool
        let host: String
        let port: String
    }

    static func currentSOCKS(service: String) -> SOCKSState? {
        let result = Shell.run(networksetup, ["-getsocksfirewallproxy", service])
        guard result.ok else { return nil }
        var enabled = false, host = "", port = ""
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "Enabled": enabled = parts[1] == "Yes"
            case "Server": host = parts[1]
            case "Port": port = parts[1]
            default: break
            }
        }
        return SOCKSState(enabled: enabled, host: host, port: port)
    }

    /// Point the service's SOCKS proxy at host:port and enable it.
    @discardableResult
    static func setSOCKS(service: String, host: String, port: UInt16) -> Result<Void, ProxyError> {
        let set = Shell.run(networksetup, ["-setsocksfirewallproxy", service, host, String(port)])
        guard set.ok else { return .failure(errorText(set)) }
        // `-setsocksfirewallproxy` enables by default, but be explicit.
        let on = Shell.run(networksetup, ["-setsocksfirewallproxystate", service, "on"])
        guard on.ok else { return .failure(errorText(on)) }
        return .success(())
    }

    @discardableResult
    static func disableSOCKS(service: String) -> Result<Void, ProxyError> {
        let off = Shell.run(networksetup, ["-setsocksfirewallproxystate", service, "off"])
        guard off.ok else { return .failure(errorText(off)) }
        return .success(())
    }

    /// Enable the SOCKS proxy on *every* configurable service. macOS applies
    /// only the currently-active primary service's proxy to apps, and that
    /// primary changes as Wi-Fi/USB come and go — so we set them all, and
    /// whichever is active is always covered. Returns the services we touched
    /// (to undo exactly those later) and any per-service failures.
    static func setSOCKSOnAll(host: String, port: UInt16) -> (applied: [String], failed: [(String, String)]) {
        var applied: [String] = []
        var failed: [(String, String)] = []
        for service in networkServices() {
            switch setSOCKS(service: service, host: host, port: port) {
            case .success: applied.append(service)
            case .failure(let e): failed.append((service, e.message))
            }
        }
        return (applied, failed)
    }

    /// Disable the SOCKS proxy on the given services (or all, if nil).
    static func disableSOCKSOnAll(services: [String]? = nil) {
        for service in services ?? networkServices() {
            _ = disableSOCKS(service: service)
        }
    }

    private static func errorText(_ r: ShellResult) -> ProxyError {
        let combined = (r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        return ProxyError(message: combined.isEmpty ? "networksetup exited \(r.exitCode)" : combined)
    }
}
