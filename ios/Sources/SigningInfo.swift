import Foundation

/// Reads the app's embedded provisioning profile to surface how long the
/// current (re)signing is valid — the crux of the free-Apple-ID "7-day" problem
/// (spec §7). Sideloaded builds carry `embedded.mobileprovision`; the profile's
/// `ExpirationDate` tells us when the app stops launching.
///
/// The file is a CMS/PKCS#7 blob with a plaintext XML plist embedded inside it,
/// so we slice out the `<plist>…</plist>` span and parse that. `parse(data:)`
/// is separated from bundle access so it can be exercised in isolation.
struct SigningInfo: Equatable {
    let name: String?
    let teamName: String?
    let expirationDate: Date?

    /// Whole days until expiry (0 if today, negative if already expired).
    /// `nil` when there is no expiration date (e.g. App Store / no profile).
    func daysRemaining(now: Date = Date()) -> Int? {
        guard let expirationDate else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: now)
        let end = cal.startOfDay(for: expirationDate)
        return cal.dateComponents([.day], from: start, to: end).day
    }

    // MARK: - Loading

    /// Parse the app's own `embedded.mobileprovision`. Returns `nil` when the
    /// bundle has no profile (App Store builds, simulator, unsigned dev runs).
    static func current(bundle: Bundle = .main) -> SigningInfo? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return parse(data: data)
    }

    /// Extract the embedded XML plist from a `.mobileprovision` blob and read
    /// the fields we care about. Returns `nil` if no plist can be located.
    static func parse(data: Data) -> SigningInfo? {
        guard let plistData = extractPlist(from: data),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
              let dict = plist as? [String: Any] else {
            return nil
        }
        return SigningInfo(
            name: dict["Name"] as? String,
            teamName: dict["TeamName"] as? String,
            expirationDate: dict["ExpirationDate"] as? Date
        )
    }

    /// Locate the `<plist …>…</plist>` byte range inside the surrounding CMS.
    private static func extractPlist(from data: Data) -> Data? {
        let open = Data("<plist".utf8)
        let close = Data("</plist>".utf8)
        guard let start = data.range(of: open),
              let end = data.range(of: close, in: start.upperBound..<data.endIndex) else {
            return nil
        }
        return data.subdata(in: start.lowerBound..<end.upperBound)
    }
}
