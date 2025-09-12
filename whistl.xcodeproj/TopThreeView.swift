//
//  TopThreeView.swift
//  com.whistl.whistl.reportextension
//

import SwiftUI
import DeviceActivity

struct TopThreeView: DeviceActivityReportView {
    let report: TopThreeReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top apps by time")
                .font(.headline)

            ForEach(report.topApps.indices, id: \.self) { i in
                let app = report.topApps[i]
                HStack {
                    Text("\(i+1). \(app.name)")
                    Spacer()
                    Text(formatMinutes(app.duration))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    private func formatMinutes(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        return "\(m)m"
    }
}

