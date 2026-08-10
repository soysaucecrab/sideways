import Foundation

/// Drives the root TUN scripts. After a one-time install (single auth prompt),
/// the scripts live in a root-owned dir and run through passwordless `sudo`, so
/// starting/stopping the tunnel needs no further authentication.
enum TunHelper {
    static let dir = "/usr/local/libexec/datasharing"
    /// Bump when the bundled scripts change so `install()` re-copies them.
    static let version = "2"

    struct Result { let ok: Bool; let output: String }

    /// True when the installed helper matches the current bundled version.
    static var isInstalled: Bool {
        guard let v = try? String(contentsOfFile: "\(dir)/.version", encoding: .utf8) else { return false }
        return v.trimmingCharacters(in: .whitespacesAndNewlines) == version
    }

    /// Run an installed script with passwordless sudo (no prompt). Blocking.
    @discardableResult
    static func run(_ script: String) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", "\(dir)/\(script)"]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            _ = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return Result(ok: p.terminationStatus == 0, output: text)
        } catch {
            return Result(ok: false, output: "\(error)")
        }
    }

    /// One-time (or on-update) install via a single macOS auth prompt. Copies
    /// the bundled scripts to a root-owned dir and grants passwordless sudo.
    static func install() -> Bool {
        guard let res = Bundle.main.resourcePath else { return false }
        let helper = "\(res)/install-helper.sh"
        guard FileManager.default.fileExists(atPath: helper) else { return false }
        let shell = "bash '\(shEsc(helper))' '\(shEsc(res))' '\(version)'"
        let apple = "do shell script \"\(aplEsc(shell))\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", apple]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            return p.terminationStatus == 0 && text.contains("ok")
        } catch {
            return false
        }
    }

    private static func shEsc(_ s: String) -> String { s.replacingOccurrences(of: "'", with: "'\\''") }
    private static func aplEsc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
