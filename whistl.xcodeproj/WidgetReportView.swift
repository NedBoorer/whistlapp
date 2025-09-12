//
//  WidgetReportView.swift
//  com.whistl.whistl.reportextension
//

import SwiftUI
import DeviceActivity

struct WidgetReportView: DeviceActivityReportView {
    let report: TotalActivityWidgetReport

    var body: some View {
        VStack(spacing: 6) {
            Text("Today")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(report.totalMinutes))m")
                .font(.title2.bold())
        }
        .padding()
    }
}

