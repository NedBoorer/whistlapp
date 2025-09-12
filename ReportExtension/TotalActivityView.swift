//
//  TotalActivityView.swift
//  ReportExtension
//
//  Created by Ned Boorer on 12/9/2025.
//

import SwiftUI

struct TotalActivityView: View {
    let model: ActivityReport

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var body: some View {
        List {
            Section("Total") {
                HStack {
                    Text("Screen time")
                    Spacer()
                    Text(formatDuration(model.totalDuration))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Pickups")
                    Spacer()
                    Text("\(model.totalPickups)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Longest session")
                    Spacer()
                    Text(formatDuration(model.longestActivity))
                        .foregroundStyle(.secondary)
                }
                if let first = model.firstPickup {
                    HStack {
                        Text("First pickup")
                        Spacer()
                        Text(first.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !model.categories.isEmpty {
                Section("By category") {
                    ForEach(model.categories) { cat in
                        HStack {
                            Text(cat.name)
                            Spacer()
                            Text(formatDuration(cat.duration))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.apps.isEmpty {
                Section("By app") {
                    ForEach(model.apps.prefix(10)) { app in
                        HStack {
                            Text(app.name)
                            Spacer()
                            Text(formatDuration(app.duration))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    TotalActivityView(model: ActivityReport(
        totalDuration: 7200,
        totalPickups: 12,
        longestActivity: 1800,
        firstPickup: Date(),
        categories: [
            CategoryDeviceActivity(name: "Social", duration: 3600),
            CategoryDeviceActivity(name: "Productivity", duration: 1800)
        ],
        apps: [
            AppDeviceActivity(name: "Messages", bundleIdentifier: "com.apple.MobileSMS", duration: 2400, numberOfPickups: 3, numberOfNotifications: 5),
            AppDeviceActivity(name: "Safari", bundleIdentifier: "com.apple.mobilesafari", duration: 1800, numberOfPickups: 2, numberOfNotifications: 1)
        ]
    ))
}

