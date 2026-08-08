import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var stats: ProxyStats
    @ObservedObject var controller: ProxyController

    @State private var portText = "8888"

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
}
