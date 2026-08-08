import Foundation
import Combine

/// Owns the `iproxy` subprocess that bridges a Mac-local port to the iPhone's
/// SOCKS port over USB (spec §5.2), plus the system-proxy toggle. This is the
/// single source of truth for the menu-bar UI's state.
final class TunnelManager: ObservableObject {

    enum Status: Equatable {
        case idle
        case running
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var deviceName: String?     // connected iPhone, if detected
    @Published private(set) var lastLog: String = ""

    // User-configurable (persisted by the view via @AppStorage-backed values).
    @Published var macPort: UInt16 = 8888
    @Published var iphonePort: UInt16 = 8888
    @Published var service: String = "Wi-Fi"

    private var iproxyProcess: Process?
    private let workQueue = DispatchQueue(label: "tunnel.manager")

    // Homebrew tools live in different prefixes on Intel vs Apple Silicon.
    private var iproxyPath: String? {
        Shell.firstExisting([
            "/opt/homebrew/bin/iproxy",
            "/usr/local/bin/iproxy",
        ])
    }
    private var ideviceIDPath: String? {
        Shell.firstExisting([
            "/opt/homebrew/bin/idevice_id",
            "/usr/local/bin/idevice_id",
        ])
    }

    var isRunning: Bool { status == .running }

    // MARK: - Device detection (UDID / name)

    /// UI entry point: detect a connected iPhone off the main thread and publish
    /// the result. Use this from views; `startLocked` calls the sync variant
    /// directly because it already runs on `workQueue`.
    func refreshDevice() {
        workQueue.async { [weak self] in _ = self?.detectDevice() }
    }

    /// Detect a connected, trusted iPhone. Updates `deviceName`; returns the
    /// first UDID if any. Best-effort — the tunnel still works without a name.
    /// Blocking (runs `idevice_id`); call on `workQueue`, never on main.
    @discardableResult
    private func detectDevice() -> String? {
        guard let ideviceID = ideviceIDPath else {
            DispatchQueue.main.async { self.deviceName = nil }
            return nil
        }
        let list = Shell.run(ideviceID, ["-l"])
        let udid = list.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }

        var name: String?
        if let udid,
           let ideviceinfo = Shell.firstExisting(["/opt/homebrew/bin/ideviceinfo", "/usr/local/bin/ideviceinfo"]) {
            let info = Shell.run(ideviceinfo, ["-u", udid, "-k", "DeviceName"])
            if info.ok {
                let n = info.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                name = n.isEmpty ? udid : n
            } else {
                name = udid
            }
        } else {
            name = udid
        }
        DispatchQueue.main.async { self.deviceName = name }
        return udid
    }

    // MARK: - Start / stop

    func start() {
        workQueue.async { [weak self] in self?.startLocked() }
    }

    private func startLocked() {
        guard iproxyProcess == nil else { return }

        guard let iproxy = iproxyPath else {
            setStatus(.failed("iproxy를 찾을 수 없습니다. 'brew install libimobiledevice'로 설치하세요."))
            return
        }

        let udid = detectDevice()

        // 1) Launch iproxy: forward macPort -> iphonePort over USB.
        var args = ["\(macPort):\(iphonePort)"]
        if let udid { args += ["-u", udid] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: iproxy)
        process.arguments = args

        let logPipe = Pipe()
        process.standardOutput = logPipe
        process.standardError = logPipe
        logPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.lastLog = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.workQueue.async {
                self.iproxyProcess = nil
                // If it dies while we thought we were running, reflect that and
                // undo the system-proxy change so the Mac isn't left offline.
                if self.isRunningFlag {
                    self.isRunningFlag = false
                    _ = ProxyConfigurator.disableSOCKS(service: self.service)
                    self.setStatus(.failed("iproxy가 종료되었습니다 (코드 \(proc.terminationStatus)). iPhone 연결/잠금 해제를 확인하세요."))
                }
            }
        }

        do {
            try process.run()
        } catch {
            setStatus(.failed("iproxy 실행 실패: \(error.localizedDescription)"))
            return
        }
        iproxyProcess = process

        // 2) Point the system SOCKS proxy at the forwarded local port.
        switch ProxyConfigurator.setSOCKS(service: service, host: "127.0.0.1", port: macPort) {
        case .success:
            isRunningFlag = true
            setStatus(.running)
        case .failure(let message):
            // Roll back the tunnel so we don't leave iproxy running with no proxy.
            process.terminationHandler = nil
            process.terminate()
            iproxyProcess = nil
            setStatus(.failed("프록시 설정 실패: \(message.message)"))
        }
    }

    func stop() {
        workQueue.async { [weak self] in self?.stopLocked() }
    }

    private func stopLocked() {
        isRunningFlag = false

        // Undo the system-proxy change first so the Mac regains normal networking.
        let disable = ProxyConfigurator.disableSOCKS(service: service)

        if let process = iproxyProcess {
            process.terminationHandler = nil
            process.terminate()
            iproxyProcess = nil
        }

        switch disable {
        case .success:
            setStatus(.idle)
        case .failure(let message):
            setStatus(.failed("프록시 해제 실패: \(message.message)"))
        }
    }

    // MARK: - Internal state

    /// Tracks whether we consider ourselves "on" independent of the published
    /// enum, so the termination handler can tell a crash from an intended stop.
    private var isRunningFlag = false

    private func setStatus(_ new: Status) {
        DispatchQueue.main.async { self.status = new }
    }

    deinit {
        // Best-effort cleanup if the app quits while running.
        if isRunningFlag {
            _ = ProxyConfigurator.disableSOCKS(service: service)
        }
        iproxyProcess?.terminate()
    }
}
