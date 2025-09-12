//
//  TotalActivityReport.swift
//  com.whistl.whistl.reportextension
//

import DeviceActivity
import SwiftUI

struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalActivity

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> some DeviceActivityReport.Configuration {
        var totalDuration: TimeInterval = 0
        var pickups: Int = 0
        var longestSession: TimeInterval = 0
        var firstPickup: Date? = nil

        var categories: [CategoryDeviceActivity] = []
        var apps: [AppDeviceActivity] = []

        for await result in data {
            for await segment in result.activitySegments {
                totalDuration += segment.totalActivityDuration
                pickups += segment.totalPickupsWithoutApplicationActivity
                if segment.longestActivity > longestSession {
                    longestSession = segment.longestActivity
                }
                if firstPickup == nil, let fp = segment.firstPickup {
                    firstPickup = fp
                }

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

        let report = ActivityReport(
            totalDuration: totalDuration,
            pickups: pickups,
            longestSession: longestSession,
            firstPickup: firstPickup,
            categories: categories,
            apps: apps
        )
        return TotalActivityView(report: report)
    }
}

