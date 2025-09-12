//
//  TotalActivityReport.swift
//  ReportExtension
//
//  Created by Ned Boorer on 12/9/2025.
//

import DeviceActivity
import ExtensionKit
import SwiftUI
import ManagedSettings

// MARK: - Contexts supported by your reports

extension DeviceActivityReport.Context {
    // Used for a "home" summary page
    static let home = Self("Home")
    // Detailed total activity page
    static let totalActivity = Self("Total Activity")
    // Small widget-like summary
    static let widget = Self("Widget")
    // More insights like pickups/notifications
    static let moreInsights = Self("More Insights")
    // Top apps list
    static let topApps = Self("Top Apps")
    // Total pickups chart
    static let totalPickups = Self("Total Pickups")
}

// MARK: - Models

struct AppDeviceActivity: Identifiable, Hashable {
    var id: String { bundleIdentifier ?? name }
    let name: String
    let bundleIdentifier: String?
    let duration: TimeInterval
    let numberOfPickups: Int
    let numberOfNotifications: Int
}

struct CategoryDeviceActivity: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let duration: TimeInterval
}

struct ActivityReport: Hashable {
    let totalDuration: TimeInterval
    let totalPickups: Int
    let longestActivity: TimeInterval
    let firstPickup: Date?
    let categories: [CategoryDeviceActivity]
    let apps: [AppDeviceActivity]
}

struct TopThreeReport: Hashable {
    let topApps: [AppDeviceActivity] // already sorted by duration desc, max 3
}

// Small value types to avoid tuples in arrays for Hashable/Equatable synthesis
struct NamedMinutes: Hashable {
    let name: String
    let value: Double
}

struct NamedCount: Hashable {
    let name: String
    let value: Double
}

struct ChartAndTopThreeReport: Hashable {
    let totalDuration: TimeInterval
    let categoryMinutes: [NamedMinutes]
    let appMinutes: [NamedMinutes]
    let topThree: [AppDeviceActivity]
}

struct MoreInsightsReport: Hashable {
    let totalPickups: Int
    let pickupsByApp: [NamedCount]
    let notificationsByApp: [NamedCount]
}

struct TotalActivityWidgetReport: Hashable {
    let totalDuration: TimeInterval
    let topAppName: String?
    let topAppMinutes: Double
}

// MARK: - Scenes

struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalActivity
    let content: (ActivityReport) -> TotalActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ActivityReport {
        var totalDuration: TimeInterval = 0
        var totalPickups = 0
        var longestActivity: TimeInterval = 0
        var firstPickup: Date?

        var categoryDurations: [String: TimeInterval] = [:]
        var appsMap: [String: AppDeviceActivity] = [:]

        for await segment in data.flatMap({ $0.activitySegments }) {
            totalDuration += segment.totalActivityDuration
            totalPickups += segment.totalPickupsWithoutApplicationActivity

            // Some SDKs do not expose longestActivityDuration; approximate with segment total
            longestActivity = max(longestActivity, segment.totalActivityDuration)

            if let segFirst = segment.firstPickup, (firstPickup == nil || segFirst < firstPickup!) {
                firstPickup = segFirst
            }

            for await category in segment.categories {
                let catName = category.category.localizedDisplayName ?? "Category"
                categoryDurations[catName, default: 0] += category.totalActivityDuration

                for await app in category.applications {
                    let name = app.application.localizedDisplayName ?? "App"
                    let bundleId = app.application.bundleIdentifier
                    let key = bundleId ?? name
                    let existing = appsMap[key]
                    let merged = AppDeviceActivity(
                        name: name,
                        bundleIdentifier: bundleId,
                        duration: (existing?.duration ?? 0) + app.totalActivityDuration,
                        numberOfPickups: (existing?.numberOfPickups ?? 0) + app.numberOfPickups,
                        numberOfNotifications: (existing?.numberOfNotifications ?? 0) + app.numberOfNotifications
                    )
                    appsMap[key] = merged
                }
            }
        }

        let categories = categoryDurations
            .map { CategoryDeviceActivity(name: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }

        let apps = Array(appsMap.values).sorted { $0.duration > $1.duration }

        return ActivityReport(
            totalDuration: totalDuration,
            totalPickups: totalPickups,
            longestActivity: longestActivity,
            firstPickup: firstPickup,
            categories: categories,
            apps: apps
        )
    }
}

struct HomeReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .home
    let content: (ChartAndTopThreeReport) -> HomeReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ChartAndTopThreeReport {
        var totalDuration: TimeInterval = 0
        var categoryDurations: [String: TimeInterval] = [:]
        var appDurations: [String: TimeInterval] = [:]

        for await segment in data.flatMap({ $0.activitySegments }) {
            totalDuration += segment.totalActivityDuration

            for await category in segment.categories {
                let catName = category.category.localizedDisplayName ?? "Category"
                categoryDurations[catName, default: 0] += category.totalActivityDuration

                for await app in category.applications {
                    let name = app.application.localizedDisplayName ?? "App"
                    appDurations[name, default: 0] += app.totalActivityDuration
                }
            }
        }

        let categoryMinutes: [NamedMinutes] = categoryDurations
            .map { NamedMinutes(name: $0.key, value: $0.value / 60.0) }
            .sorted { $0.value > $1.value }

        let appMinutes: [NamedMinutes] = appDurations
            .map { NamedMinutes(name: $0.key, value: $0.value / 60.0) }
            .sorted { $0.value > $1.value }

        let topThree = appDurations
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (name, duration) in
                AppDeviceActivity(name: name, bundleIdentifier: nil, duration: duration, numberOfPickups: 0, numberOfNotifications: 0)
            }

        return ChartAndTopThreeReport(
            totalDuration: totalDuration,
            categoryMinutes: categoryMinutes,
            appMinutes: appMinutes,
            topThree: topThree
        )
    }
}

struct TopAppsReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .topApps
    let content: (TopThreeReport) -> TopThreeView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TopThreeReport {
        var appDurations: [String: (name: String, duration: TimeInterval)] = [:]

        for await segment in data.flatMap({ $0.activitySegments }) {
            for await category in segment.categories {
                for await app in category.applications {
                    let name = app.application.localizedDisplayName ?? "App"
                    let key = app.application.bundleIdentifier ?? name
                    let current = appDurations[key]?.duration ?? 0
                    appDurations[key] = (name, current + app.totalActivityDuration)
                }
            }
        }

        let top = appDurations
            .sorted { $0.value.duration > $1.value.duration }
            .prefix(3)
            .map { entry in
                AppDeviceActivity(name: entry.value.name, bundleIdentifier: entry.key, duration: entry.value.duration, numberOfPickups: 0, numberOfNotifications: 0)
            }

        return TopThreeReport(topApps: Array(top))
    }
}

struct TotalPickupsReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalPickups
    let content: (MoreInsightsReport) -> PickupsChartView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> MoreInsightsReport {
        var totalPickups = 0
        var pickupsByApp: [String: Int] = [:]
        var notificationsByApp: [String: Int] = [:]

        for await segment in data.flatMap({ $0.activitySegments }) {
            totalPickups += segment.totalPickupsWithoutApplicationActivity

            for await category in segment.categories {
                for await app in category.applications {
                    let name = app.application.localizedDisplayName ?? "App"
                    pickupsByApp[name, default: 0] += app.numberOfPickups
                    notificationsByApp[name, default: 0] += app.numberOfNotifications
                }
            }
        }

        let pickupsPairs: [NamedCount] = pickupsByApp
            .map { NamedCount(name: $0.key, value: Double($0.value)) }
            .sorted { $0.value > $1.value }

        let notificationsPairs: [NamedCount] = notificationsByApp
            .map { NamedCount(name: $0.key, value: Double($0.value)) }
            .sorted { $0.value > $1.value }

        return MoreInsightsReport(
            totalPickups: totalPickups,
            pickupsByApp: pickupsPairs,
            notificationsByApp: notificationsPairs
        )
    }
}

struct WidgetReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .widget
    let content: (TotalActivityWidgetReport) -> WidgetReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TotalActivityWidgetReport {
        var totalDuration: TimeInterval = 0
        var appDurations: [String: (name: String, duration: TimeInterval)] = [:]

        for await segment in data.flatMap({ $0.activitySegments }) {
            totalDuration += segment.totalActivityDuration

            for await category in segment.categories {
                for await app in category.applications {
                    let name = app.application.localizedDisplayName ?? "App"
                    let key = app.application.bundleIdentifier ?? name
                    let current = appDurations[key]?.duration ?? 0
                    appDurations[key] = (name, current + app.totalActivityDuration)
                }
            }
        }

        let top = appDurations.max(by: { $0.value.duration < $1.value.duration })
        let topName = top?.value.name
        let topMinutes = (top?.value.duration ?? 0) / 60.0

        return TotalActivityWidgetReport(
            totalDuration: totalDuration,
            topAppName: topName,
            topAppMinutes: topMinutes
        )
    }
}
