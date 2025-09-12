//
//  TopThreeView.swift
//  ReportExtension
//
//  Created by Ned Boorer on 12/9/2025.
//

import SwiftUI

struct TopThreeView: View {
    let model: TopThreeReport

    var body: some View {
        List {
            Section("Top apps by time") {
                ForEach(model.topApps) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        Text("\(Int(app.duration/60))m")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    TopThreeView(model: TopThreeReport(topApps: [
        AppDeviceActivity(name: "Messages", bundleIdentifier: nil, duration: 3200, numberOfPickups: 0, numberOfNotifications: 0),
        AppDeviceActivity(name: "Safari", bundleIdentifier: nil, duration: 2100, numberOfPickups: 0, numberOfNotifications: 0),
        AppDeviceActivity(name: "YouTube", bundleIdentifier: nil, duration: 1800, numberOfPickups: 0, numberOfNotifications: 0)
    ]))
}

