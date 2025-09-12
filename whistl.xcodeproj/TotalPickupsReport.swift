//
//  TotalPickupsReport.swift
//  com.whistl.whistl.reportextension
//

import DeviceActivity
import SwiftUI

struct TotalPickupsReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalPickups

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

        let pickupsChart = apps
            .sorted { $0.numberOfPickups > $1.numberOfPickups }
            .prefix(5)
            .map { ($0.name, Double($0.numberOfPickups)) }

        let notificationsChart = apps
            .sorted { $0.numberOfNotifications > $1.numberOfNotifications }
            .prefix(5)
            .map { ($0.name, Double($0.numberOfNotifications)) }

        let report = MoreInsightsReport(
            pickupsChart: Array(pickupsChart),
            notificationsChart: Array(notificationsChart)
        )
        return PickupsChartView(report: report)
    }
}

