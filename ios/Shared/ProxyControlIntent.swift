import AppIntents

/// Toggle intent backing the Control Center control. It MUST be compiled into
/// BOTH the app and the widget-extension target: iOS resolves the intent from
/// the app to know which app to foreground, so an extension-only intent leaves
/// the control inert (tapping does nothing). Hence its home in Shared/.
///
/// The proxy is foreground-only, so the intent opens the app (openAppWhenRun);
/// the app then applies the desired state on activation.
struct ToggleProxyIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Data Sharing 프록시 전환"
    static let openAppWhenRun: Bool = true

    @Parameter(title: "켜기")
    var value: Bool

    func perform() async throws -> some IntentResult {
        SharedState.setDesired(value)
        return .result()
    }
}
