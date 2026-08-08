import UIKit

/// Deep-links into AltStore (or SideStore) so the user can refresh this app's
/// 7-day signing without leaving the workflow. We can't silently re-sign — only
/// AltServer/AltStore can — so the button foregrounds AltStore where "Refresh
/// All" lives.
///
/// `canOpen` relies on `LSApplicationQueriesSchemes` listing `altstore` and
/// `sidestore` in Info.plist; without that, `canOpenURL` always returns false.
enum AltStoreLink {
    /// AltStore first, then the SideStore fork, in preference order.
    static let candidates: [URL] = [
        URL(string: "altstore://")!,
        URL(string: "sidestore://")!,
    ]

    /// The first installed store's URL, if any.
    static func installedURL() -> URL? {
        candidates.first { UIApplication.shared.canOpenURL($0) }
    }

    static var isInstalled: Bool { installedURL() != nil }

    /// Open the installed store. Completion reports whether a store opened.
    static func open(completion: ((Bool) -> Void)? = nil) {
        guard let url = installedURL() else { completion?(false); return }
        UIApplication.shared.open(url, options: [:]) { completion?($0) }
    }
}
