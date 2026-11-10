import Foundation

/// Point-in-time proxy state, sent from the packet tunnel extension to the app
/// in reply to `NETunnelProviderSession.sendProviderMessage`. The SOCKS server
/// lives in the extension process, so this is the app's only view of it.
struct TunnelSnapshot: Codable {
    var isRunning = false
    var port: UInt16 = 8888
    var activeConnections = 0
    var bytesIn = 0     // internet → Mac, this tunnel session
    var bytesOut = 0    // Mac → internet, this tunnel session
    var rateIn = 0      // bytes/sec
    var rateOut = 0     // bytes/sec
    var lastError: String?
}
