import Foundation

/// Runs the bundled TUN scripts (sing-box + DNS injection) as root through a
/// single macOS authentication prompt (password or Touch ID). The scripts and
/// their `config.json` are copied into the app bundle's Resources at build time.
///
/// This is the pragmatic elevation path for a personal, self-signed tool: no
/// persistent privileged helper, so each start/stop shows one auth prompt.
enum TunHelper {
    struct Result { let ok: Bool; let output: String }

    private static func scriptPath(_ name: String) -> String? {
        guard let res = Bundle.main.resourcePath else { return nil }
        return "\(res)/\(name)"
    }

    /// Runs `bash <script>` as root. Blocking (shows the auth prompt) — never
    /// call on the main thread.
    @discardableResult
    static func runPrivileged(script name: String) -> Result {
        guard let path = scriptPath(name),
              FileManager.default.fileExists(atPath: path) else {
            return Result(ok: false, output: "script_not_found")
        }
        // Single-quote the path for the shell; then escape for AppleScript.
        let shellCmd = "bash '\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
        let apple = "do shell script \"\(appleEscape(shellCmd))\" with administrator privileges"

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", apple]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            _ = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Result(ok: p.terminationStatus == 0, output: text)
        } catch {
            return Result(ok: false, output: "\(error)")
        }
    }

    private static func appleEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
