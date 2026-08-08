import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var stats: ProxyStats
    @ObservedObject var controller: ProxyController

    @State private var portText = "8888"
    @State private var signing: SigningInfo? = SigningInfo.current()
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Circle()
                            .fill(stats.isRunning ? .green : .secondary)
                            .frame(width: 10, height: 10)
                        Text(stats.isRunning ? "실행 중" : "중지됨")
                            .font(.headline)
                        Spacer()
                        Text("포트 \(String(stats.listenPort))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } header: {
                    Text("상태")
                }

                Section {
                    LabeledContent("활성 연결") {
                        Text("\(stats.activeConnections)").monospacedDigit()
                    }
                    LabeledContent("수신 (인터넷→Mac)") {
                        Text(stats.bytesInText).monospacedDigit()
                    }
                    LabeledContent("송신 (Mac→인터넷)") {
                        Text(stats.bytesOutText).monospacedDigit()
                    }
                } header: {
                    Text("통계")
                }

                Section {
                    HStack {
                        Text("리슨 포트")
                        Spacer()
                        TextField("8888", text: $portText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .disabled(stats.isRunning)
                    }
                    Toggle("셀룰러 강제", isOn: $controller.requireCellular)
                        .disabled(stats.isRunning)
                } header: {
                    Text("설정")
                } footer: {
                    Text("셀룰러 강제를 끄면 Wi‑Fi로도 나갈 수 있어 디버깅에 유용합니다. 실사용 시 켜 두세요.")
                }

                signingSection

                if let error = stats.lastError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } header: {
                        Text("마지막 오류")
                    }
                }

                Section {
                    Button {
                        toggle()
                    } label: {
                        Text(stats.isRunning ? "중지" : "시작")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(stats.isRunning ? .red : .accentColor)
                }
            }
            .navigationTitle("Data Sharing")
            .onAppear { portText = String(stats.listenPort) }
        }
    }

    private func toggle() {
        if stats.isRunning {
            controller.stop()
        } else {
            let port = UInt16(portText) ?? 8888
            controller.start(port: port)
        }
    }

    // MARK: - Signing / AltStore refresh

    @ViewBuilder
    private var signingSection: some View {
        if let signing, signing.expirationDate != nil {
            Section {
                LabeledContent("만료일") {
                    Text(expiryDateText(signing)).monospacedDigit()
                }
                LabeledContent("남은 기간") {
                    Text(daysRemainingText(signing))
                        .foregroundStyle(expiryColor(signing))
                        .monospacedDigit()
                }
                Button {
                    AltStoreLink.open { opened in
                        if !opened {
                            // Fall through to whatever handler the system has.
                            openURL(AltStoreLink.candidates[0])
                        }
                    }
                } label: {
                    Label("AltStore에서 갱신", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("서명")
            } footer: {
                Text("무료 Apple ID 서명은 7일 후 만료됩니다. AltStore(AltServer)가 만료 전 자동 갱신하며, 위 버튼으로 즉시 갱신할 수 있습니다.")
            }
        }
    }

    private func expiryDateText(_ info: SigningInfo) -> String {
        guard let date = info.expirationDate else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    private func daysRemainingText(_ info: SigningInfo) -> String {
        guard let days = info.daysRemaining() else { return "—" }
        if days < 0 { return "만료됨" }
        if days == 0 { return "오늘 만료" }
        return "\(days)일"
    }

    private func expiryColor(_ info: SigningInfo) -> Color {
        guard let days = info.daysRemaining() else { return .primary }
        if days <= 0 { return .red }
        if days <= 2 { return .orange }
        return .primary
    }
}
