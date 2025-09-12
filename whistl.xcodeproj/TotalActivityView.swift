//
//  TotalActivityView.swift
//  com.whistl.whistl.reportextension
//

import SwiftUI
import DeviceActivity

struct TotalActivityView: DeviceActivityReportView {
    let report: ActivityReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Total screen time")
                    .font(.headline)
                Spacer()
                Text(formatHM(report.totalDuration))
                    .font(.headline)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Pickups")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(report.pickups)")
                        .font(.title3.bold())
                }
                VStack(alignment: .leading) {
                    Text("Longest session")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(formatHM(report.longestSession))
                        .font(.title3.bold())
                }
                VStack(alignment: .leading) {
                    Text("First pickup")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(report.firstPickup.map { formatTime($0) } ?? "—")
                        .font(.title3.bold())
                }
            }

            Divider()

            Text("Top categories")
                .font(.headline)
            MiniBars(pairs: report.categories
                .sorted { $0.duration > $1.duration }
                .prefix(5)
                .map { ($0.name, $0.duration / 60.0) }
            )

            Text("Top apps")
                .font(.headline)
            MiniBars(pairs: report.apps
                .sorted { $0.duration > $1.duration }
                .prefix(5)
                .map { ($0.name, $0.duration / 60.0) }
            )
        }
        .padding()
    }

    private func formatHM(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

