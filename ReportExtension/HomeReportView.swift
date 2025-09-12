//
//  HomeReportView.swift
//  ReportExtension
//
//  Created by Ned Boorer on 12/9/2025.
//

import SwiftUI

struct HomeReportView: View {
    let model: ChartAndTopThreeReport

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var body: some View {
        List {
            Section("Summary") {
                HStack {
                    Text("Screen time")
                    Spacer()
                    Text(formatDuration(model.totalDuration))
                        .foregroundStyle(.secondary)
                }
            }

            if !model.topThree.isEmpty {
                Section("Top apps") {
                    ForEach(model.topThree) { app in
                        HStack {
                            Text(app.name)
                            Spacer()
                            Text("\(Int(app.duration/60))m")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.categoryMinutes.isEmpty {
                Section("Categories (min)") {
                    ForEach(model.categoryMinutes.prefix(5), id: \.0) { item in
                        HStack {
                            Text(item.0)
                            Spacer()
                            Text("\(Int(item.1))m")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    HomeReportView(model: ChartAndTopThreeReport(
        totalDuration: 5400,
        categoryMinutes: [("Social", 60), ("Productivity", 30)],
        appMinutes: [("Messages", 55), ("Safari", 35)],
        topThree: [
            AppDeviceActivity(name: "Messages", bundleIdentifier: nil, duration: 3300, numberOfPickups: 0, numberOfNotifications: 0),
            AppDeviceActivity(name: "Safari", bundleIdentifier: nil, duration: 2100, numberOfPickups: 0, numberOfNotifications: 0)
        ]
    ))
}

