import Foundation

/// State shared between the app and the Control Center widget extension via
/// the app-group container. The control toggle writes a "desired" state; the
/// app consumes it on activation (the proxy is foreground-only, so the toggle
/// opens the app rather than starting the listener out-of-process).
enum SharedState {
    static let appGroupID = "group.com.zinu.datasharing"
    static let controlKind = "com.zinu.datasharing.ios.control.proxy"

    private static let runningKey = "control.isRunning"
    private static let desiredKey = "control.desired"
    private static let portKey = "control.port"
    private static let cellularKey = "control.requireCellular"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var isRunning: Bool {
        get { defaults.bool(forKey: runningKey) }
        set { defaults.set(newValue, forKey: runningKey) }
    }

    static var port: UInt16 {
        get {
            let v = defaults.integer(forKey: portKey)
            return (v > 0 && v <= 65535) ? UInt16(v) : 8888
        }
        set { defaults.set(Int(newValue), forKey: portKey) }
    }

    static var requireCellular: Bool {
        // Default off: Wi-Fi-permitted is the friendlier default; users who
        // want strict cellular pinning enable it explicitly.
        get { defaults.object(forKey: cellularKey) as? Bool ?? false }
        set { defaults.set(newValue, forKey: cellularKey) }
    }

    static func setDesired(_ on: Bool) {
        defaults.set(on, forKey: desiredKey)
    }

    /// Returns the pending desired state (if any) and clears it, so a stale
    /// request never re-fires on a later activation.
    static func takeDesired() -> Bool? {
        guard defaults.object(forKey: desiredKey) != nil else { return nil }
        let v = defaults.bool(forKey: desiredKey)
        defaults.removeObject(forKey: desiredKey)
        return v
    }
}
