import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var stats: ProxyStats
    @EnvironmentObject private var usage: UsageStore
    @ObservedObject var controller: ProxyController

    @State private var portText = "8888"
    @State private var signing: SigningInfo? = SigningInfo.current()

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
                } footer: {
                    Text("켜두면 앱을 나가거나 화면을 꺼도 계속 동작합니다. 실행 중에는 상단에 VPN 표시가 나타납니다.")
                }

                Section {
                    LabeledContent("다운로드 속도") {
                        Text(stats.rateInText).monospacedDigit()
                    }
                    LabeledContent("업로드 속도") {
                        Text(stats.rateOutText).monospacedDigit()
                    }
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
                    NavigationLink {
                        UsageView()
                    } label: {
                        Label("누적 사용량", systemImage: "chart.bar.fill")
                    }
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

    // MARK: - Signing

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
            } header: {
                Text("서명")
            } footer: {
                Text("개발자 서명은 만료일까지 유효합니다. 만료 전에 Xcode로 다시 빌드해 설치하세요.")
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
