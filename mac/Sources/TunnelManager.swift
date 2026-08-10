import Foundation
import Combine

/// Owns the `iproxy` subprocess (USB bridge to the iPhone SOCKS port) and the
/// sing-box TUN front-end that routes *all* Mac apps through it — working even
/// with no Wi-Fi. The TUN + DNS setup needs root, so it runs via bundled
/// scripts through one macOS auth prompt (see `TunHelper`).
final class TunnelManager: ObservableObject {

    enum Status: Equatable {
        case idle
        case running
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var deviceName: String?     // connected iPhone, if detected
    @Published private(set) var lastLog: String = ""

    @Published var macPort: UInt16 = 8888
    @Published var iphonePort: UInt16 = 8888

    private var iproxyProcess: Process?
    private let workQueue = DispatchQueue(label: "tunnel.manager")

    // Homebrew tools live in different prefixes on Intel vs Apple Silicon.
    private var iproxyPath: String? {
        Shell.firstExisting(["/opt/homebrew/bin/iproxy", "/usr/local/bin/iproxy"])
    }
    private var ideviceIDPath: String? {
        Shell.firstExisting(["/opt/homebrew/bin/idevice_id", "/usr/local/bin/idevice_id"])
    }

    var isRunning: Bool { status == .running }

    // MARK: - Device detection (UDID / name)

    func refreshDevice() {
        workQueue.async { [weak self] in _ = self?.detectDevice() }
    }

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
            name = info.ok ? info.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : udid
            if name?.isEmpty == true { name = udid }
        } else {
            name = udid
        }
        DispatchQueue.main.async { self.deviceName = name }
        return udid
    }

    // MARK: - Start / stop

    func start() { workQueue.async { [weak self] in self?.startLocked() } }

    private func startLocked() {
        guard iproxyProcess == nil else { return }
        guard let iproxy = iproxyPath else {
            setStatus(.failed("iproxy를 찾을 수 없습니다. 'brew install libimobiledevice'로 설치하세요."))
            return
        }

        // One-time (or on-update) setup: single auth prompt grants passwordless
        // sudo for the TUN scripts. After this, start/stop need no auth.
        if !TunHelper.isInstalled {
            guard TunHelper.install() else {
                setStatus(.failed("최초 설정(권한 부여)에 실패했습니다. 관리자 인증을 취소했거나 실패했습니다."))
                return
            }
        }

        let udid = detectDevice()

        // Kill any stray iproxy holding our port so the new one can bind.
        _ = Shell.run("/usr/bin/pkill", ["-f", "iproxy \(macPort):"])
        Thread.sleep(forTimeInterval: 0.3)

        // 1) Launch iproxy (USB tunnel). Runs as the user.
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
                if self.isRunningFlag {
                    self.isRunningFlag = false
                    // The watchdog also cleans up, but do it here too (belt & braces).
                    _ = TunHelper.run("tun-down.sh")
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

        // 2) Bring up the TUN + DNS via passwordless sudo (no prompt). Give
        // iproxy a moment to bind first so tun-up's iproxy check passes.
        Thread.sleep(forTimeInterval: 1.2)
        let result = TunHelper.run("tun-up.sh")
        let ok = result.ok && result.output.contains("ok")
        if ok {
            isRunningFlag = true
            setStatus(.running)
        } else {
            // Roll back so we don't leave iproxy running with no tunnel.
            process.terminationHandler = nil
            process.terminate()
            iproxyProcess = nil
            setStatus(.failed(tunError(result)))
        }
    }

    func stop() { workQueue.async { [weak self] in self?.stopLocked() } }

    private func stopLocked() {
        isRunningFlag = false
        _ = TunHelper.run("tun-down.sh")  // remove routing/DNS
        if let process = iproxyProcess {
            process.terminationHandler = nil
            process.terminate()
            iproxyProcess = nil
        }
        setStatus(.idle)
    }

    /// Best-effort cleanup of a stranded tunnel from a previous crash/force-quit
    /// (in case the watchdog didn't run). Safe no-op if nothing is stale.
    func recoverStaleStateOnLaunch() {
        workQueue.async {
            guard TunHelper.isInstalled else { return }
            _ = TunHelper.run("tun-down.sh")
        }
    }

    // MARK: - Internal state

    private var isRunningFlag = false

    private func setStatus(_ new: Status) {
        DispatchQueue.main.async { self.status = new }
    }

    private func tunError(_ r: TunHelper.Result) -> String {
        if r.output.contains("iproxy_not_running") { return "터널(iproxy)이 준비되지 않았습니다. iPhone 연결/잠금 해제 확인." }
        if r.output.contains("utun_not_found") { return "sing-box 시작 실패 (utun 없음). 'brew install sing-box' 확인." }
        if r.output.isEmpty { return "관리자 인증이 취소되었거나 실패했습니다." }
        return "터널 설정 실패: \(r.output)"
    }

    deinit {
        // App quitting: best-effort. Full TUN/DNS cleanup needs root — use 중지.
        iproxyProcess?.terminate()
    }
}
