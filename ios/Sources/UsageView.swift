import SwiftUI

/// Cumulative-usage detail screen (pushed from ContentView): today, this
/// month, and all-time totals, plus a recent-days breakdown. Reads the
/// persistent `UsageStore` from the environment.
struct UsageView: View {
    @EnvironmentObject private var usage: UsageStore

    var body: some View {
        Form {
            Section {
                usageRow("수신", usage.todayIn)
                usageRow("송신", usage.todayOut)
                totalRow(usage.todayIn + usage.todayOut)
            } header: {
                Text("오늘")
            }

            Section {
                usageRow("수신", usage.monthIn)
                usageRow("송신", usage.monthOut)
                totalRow(usage.monthIn + usage.monthOut)
            } header: {
                Text("이번 달")
            }

            Section {
                usageRow("수신", usage.totalIn)
                usageRow("송신", usage.totalOut)
                totalRow(usage.totalIn + usage.totalOut)
            } header: {
                Text("전체")
            }

            if !usage.recentDays.isEmpty {
                Section {
                    ForEach(usage.recentDays) { day in
                        LabeledContent(dayLabel(day.day)) {
                            Text(ByteFormat.string(day.total))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("최근 7일 (합계)")
                }
            }
        }
        .navigationTitle("누적 사용량")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func usageRow(_ label: String, _ bytes: Int) -> some View {
        LabeledContent(label) {
            Text(ByteFormat.string(bytes)).monospacedDigit()
        }
    }

    private func totalRow(_ bytes: Int) -> some View {
        LabeledContent {
            Text(ByteFormat.string(bytes)).monospacedDigit().fontWeight(.semibold)
        } label: {
            Text("합계").fontWeight(.semibold)
        }
    }

    /// "2026-08-10" -> "8월 10일" for compactness; falls back to the raw key.
    private func dayLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else {
            return key
        }
        return "\(m)월 \(d)일"
    }
}
