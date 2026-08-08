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

    private static func errorText(_ r: ShellResult) -> ProxyError {
        let combined = (r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        return ProxyError(message: combined.isEmpty ? "networksetup exited \(r.exitCode)" : combined)
    }
}
