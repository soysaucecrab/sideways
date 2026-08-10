import WidgetKit
import SwiftUI
import AppIntents

@main
struct DataSharingControlBundle: WidgetBundle {
    var body: some Widget {
        ProxyControlWidget()
    }
}

/// Control Center toggle for the SOCKS5 proxy. The proxy only runs while the
/// app is foreground, so the intent opens the app; the app then applies the
/// desired state on activation (see ProxyController.applyDesiredFromControl).
struct ProxyControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: SharedState.controlKind,
            provider: ProxyValueProvider()
        ) { isRunning in
            ControlWidgetToggle(
                "Data Sharing",
                isOn: isRunning,
                action: ToggleProxyIntent()
            ) { isOn in
                Label(
                    isOn ? "실행 중" : "중지됨",
                    systemImage: isOn
                        ? "antenna.radiowaves.left.and.right"
                        : "antenna.radiowaves.left.and.right.slash"
                )
            }
            .tint(.blue)
        }
        .displayName("Data Sharing")
        .description("SOCKS5 프록시를 켜거나 끕니다.")
    }
}

struct ProxyValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        SharedState.isRunning
    }
}

struct ToggleProxyIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Data Sharing 프록시 전환"
    // The listener must run in the app process in the foreground, so opening
    // the app is required for both start and stop.
    static let openAppWhenRun: Bool = true

    @Parameter(title: "켜기")
    var value: Bool

    func perform() async throws -> some IntentResult {
        SharedState.setDesired(value)
        return .result()
    }
}
