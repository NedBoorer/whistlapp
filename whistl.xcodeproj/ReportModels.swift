//
//  ReportModels.swift
//  com.whistl.whistl.reportextension
//

import Foundation
import DeviceActivity
import FamilyControls

struct AppDeviceActivity: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let bundleIdentifier: String?
    let duration: TimeInterval
    let numberOfPickups: Int
    let numberOfNotifications: Int
    let token: ApplicationToken?
}

struct CategoryDeviceActivity: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let duration: TimeInterval
    let token: ActivityCategoryToken?
}

struct ActivityReport: Equatable {
    let totalDuration: TimeInterval
    let pickups: Int
    let longestSession: TimeInterval
    let firstPickup: Date?
    let categories: [CategoryDeviceActivity]
    let apps: [AppDeviceActivity]
}

struct TopThreeReport: Equatable {
    let topApps: [AppDeviceActivity] // up to 3
}

struct ChartAndTopThreeReport: Equatable {
    let categoryChart: [(String, Double)] // minutes
    let appChart: [(String, Double)]      // minutes
    let topApps: [AppDeviceActivity]
}

struct MoreInsightsReport: Equatable {
    let pickupsChart: [(String, Double)] // [(appName, pickups)]
    let notificationsChart: [(String, Double)] // [(appName, notifications)]
}

struct TotalActivityWidgetReport: Equatable {
    let totalMinutes: Double
}

