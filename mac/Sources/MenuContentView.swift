import SwiftUI

struct MenuContentView: View {
    @ObservedObject var tunnel: TunnelManager
    @AppStorage("macPort") private var macPortStore: Int = 8888
    @AppStorage("iphonePort") private var iphonePortStore: Int = 8888

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            if let device = tunnel.deviceName {
                Label(device, systemImage: "iphone")
                    .font(.callout)
            } else {
                Label("iPhone 미감지", systemImage: "iphone.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Mac 포트").foregroundStyle(.secondary)
                    TextField("8888", value: $macPortStore, format: .number.grouping(.never))
                        .frame(width: 80)
                        .disabled(tunnel.isRunning)
                }
                GridRow {
                    Text("iPhone 포트").foregroundStyle(.secondary)
                    TextField("8888", value: $iphonePortStore, format: .number.grouping(.never))
                        .frame(width: 80)
                        .disabled(tunnel.isRunning)
                }
            }
            .font(.callout)

            Label("모든 네트워크 서비스에 프록시를 자동 적용합니다 (활성 서비스가 자동 반영).",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if case .failed(let message) = tunnel.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button(tunnel.isRunning ? "중지" : "시작") {
                    toggle()
                }
                .keyboardShortcut(.defaultAction)

                Button("장치 다시 감지") {
                    tunnel.refreshDevice()
                }
                .disabled(tunnel.isRunning)

                Spacer()

                Button("종료") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear(perform: refresh)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText).font(.headline)
            Spacer()
        }
    }

    private var statusColor: Color {
        switch tunnel.status {
        case .running: return .green
        case .failed: return .red
        case .idle: return .secondary
        }
    }

    private var statusText: String {
        switch tunnel.status {
        case .running: return "공유 중 (127.0.0.1:\(tunnel.macPort))"
        case .failed: return "오류"
        case .idle: return "중지됨"
        }
    }

    private func refresh() {
        tunnel.refreshDevice()
    }

    private func toggle() {
        if tunnel.isRunning {
            tunnel.stop()
        } else {
            tunnel.macPort = UInt16(clamping: macPortStore)
            tunnel.iphonePort = UInt16(clamping: iphonePortStore)
            tunnel.start()
        }
    }
}
