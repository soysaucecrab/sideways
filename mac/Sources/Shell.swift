import Foundation

/// Result of running an external process.
struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { exitCode == 0 }
}

/// Thin wrapper over `Process` for the short-lived helper commands this app
/// runs (`networksetup`, `idevice_id`). Not for long-running processes — see
/// `TunnelManager` for the `iproxy` lifecycle.
enum Shell {
    /// Run `launchPath args…` to completion and capture output. Synchronous;
    /// call off the main thread for anything that might block.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ShellResult(exitCode: -1, stdout: "", stderr: "\(error)")
        }

        // Read before waiting to avoid deadlock on large output (fine here since
        // output is tiny, but keep the correct ordering regardless).
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// First existing path among candidates (Homebrew installs differ by arch).
    static func firstExisting(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
