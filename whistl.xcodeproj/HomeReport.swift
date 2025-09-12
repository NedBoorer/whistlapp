//
//  HomeReport.swift
//  com.whistl.whistl.reportextension
//

import DeviceActivity
import SwiftUI

struct HomeReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .home

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> some DeviceActivityReport.Configuration {
        var categories: [CategoryDeviceActivity] = []
        var apps: [AppDeviceActivity] = []

        for await result in data {
            for await segment in result.activitySegments {
                for await category in segment.categories {
                    let cat = CategoryDeviceActivity(
                        name: category.category.localizedDisplayName,
                        duration: category.totalActivityDuration,
                        token: category.category
                    )
                    categories.append(cat)

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

        // Build simple charts in minutes
        let categoryChart = categories
            .sorted { $0.duration > $1.duration }
            .prefix(5)
            .map { ($0.name, $0.duration / 60.0) }

        let appChart = apps
            .sorted { $0.duration > $1.duration }
            .prefix(5)
            .map { ($0.name, $0.duration / 60.0) }

        let topApps = Array(apps.sorted { $0.duration > $1.duration }.prefix(3))

        let report = ChartAndTopThreeReport(
            categoryChart: Array(categoryChart),
            appChart: Array(appChart),
            topApps: topApps
        )

        return HomeReportView(report: report)
    }
}

