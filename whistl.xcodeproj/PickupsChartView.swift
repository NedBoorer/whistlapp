//
//  PickupsChartView.swift
//  com.whistl.whistl.reportextension
//

import SwiftUI
import DeviceActivity

struct PickupsChartView: DeviceActivityReportView {
    let report: MoreInsightsReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pickups")
                .font(.headline)
            MiniBars(pairs: report.pickupsChart)

            Divider()

            Text("Notifications")
                .font(.headline)
            MiniBars(pairs: report.notificationsChart)
        }
        .padding()
    }
}

