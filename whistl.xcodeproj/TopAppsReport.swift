//
//  TopAppsReport.swift
//  com.whistl.whistl.reportextension
//

import DeviceActivity
import SwiftUI

struct TopAppsReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .topApps

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> some DeviceActivityReport.Configuration {
        var apps: [AppDeviceActivity] = []

        for await result in data {
            for await segment in result.activitySegments {
                for await category in segment.categories {
                    for await app in category.applications {
                        let appModel = AppDeviceActivity(
                            name: app.application.localizedDisplayName,
                            bundleIdentifier: app.application.bundleIdentifier,
                            duration: app.totalActivityDuration,
                            numberOfPickups: app.numberOfPickups,
                            numberOfNotifications: app.numberOfNotifications,
                            token: app.application
                        )
                        apps.append(appModel)
                    }
                }
            }
        }

        let topApps = Array(apps.sorted { $0.duration > $1.duration }.prefix(3))
        let report = TopThreeReport(topApps: topApps)
        return TopThreeView(report: report)
    }
}

