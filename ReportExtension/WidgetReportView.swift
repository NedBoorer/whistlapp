//
//  WidgetReportView.swift
//  ReportExtension
//
//  Created by Ned Boorer on 12/9/2025.
//

import SwiftUI

struct WidgetReportView: View {
    let model: TotalActivityWidgetReport

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screen time")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatDuration(model.totalDuration))
                .font(.title3.weight(.semibold))

            if let top = model.topAppName {
                HStack {
                    Text("Top: \(top)")
                    Spacer()
                    Text("\(Int(model.topAppMinutes))m")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
        }
        .padding()
    }
}

#Preview {
    WidgetReportView(model: TotalActivityWidgetReport(
        totalDuration: 7200,
        topAppName: "Messages",
        topAppMinutes: 55
    ))
}

