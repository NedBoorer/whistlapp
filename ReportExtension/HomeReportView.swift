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
                    ForEach(model.categoryMinutes.prefix(5), id: \.name) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text("\(Int(item.value))m")
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
        categoryMinutes: [NamedMinutes(name: "Social", value: 60), NamedMinutes(name: "Productivity", value: 30)],
        appMinutes: [NamedMinutes(name: "Messages", value: 55), NamedMinutes(name: "Safari", value: 35)],
        topThree: [
            AppDeviceActivity(name: "Messages", bundleIdentifier: nil, duration: 3300, numberOfPickups: 0, numberOfNotifications: 0),
            AppDeviceActivity(name: "Safari", bundleIdentifier: nil, duration: 2100, numberOfPickups: 0, numberOfNotifications: 0)
        ]
    ))
}
