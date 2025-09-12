//
//  ReportingScheduler.swift
//  whistl
//
//  Created by Ned Boorer on 12/9/2025.
//

import Foundation
import DeviceActivity
import FamilyControls

// Define the monitoring identifiers for the app target using DeviceActivityName.
// The report extension separately defines matching identifiers on DeviceActivityReport.Context.
extension DeviceActivityName {
    static let home = Self("Home")
    static let totalActivity = Self("Total Activity")
    static let widget = Self("Widget")
    static let moreInsights = Self("More Insights")
    static let topApps = Self("Top Apps")
    static let totalPickups = Self("Total Pickups")
}

/// Central place to keep DeviceActivityCenter monitoring in sync with SharedConfig.
/// FocusScheduleViewModel already calls refreshMonitoringFromShared() on changes.
final class ReportingScheduler {

    static let shared = ReportingScheduler()

    private let center = DeviceActivityCenter()
    private let calendar = Calendar.current

    private init() { }

    // Public API

    func refreshMonitoringFromShared() {
        Task {
            let isAuthorized = SharedConfigStore.loadIsAuthorized()
            guard isAuthorized else {
                stopAllMonitoring()
                return
            }

            let selection = SharedConfigStore.loadSelection()
            let isScheduleEnabled = SharedConfigStore.loadIsScheduleEnabled()
            let start = SharedConfigStore.loadStartMinutes()
            let end = SharedConfigStore.loadEndMinutes()

            // Create a DeviceActivitySchedule for the schedule range
            let schedule: DeviceActivitySchedule
            if isScheduleEnabled {
                let interval = scheduleRangeForToday(startMinutes: start, endMinutes: end)
                let startComponents = calendar.dateComponents([.hour, .minute], from: interval.start)
                let endComponents = calendar.dateComponents([.hour, .minute], from: interval.end)
                
                schedule = DeviceActivitySchedule(
                    intervalStart: startComponents,
                    intervalEnd: endComponents,
                    repeats: true
                )
            } else {
                // If schedule disabled, monitor "today all day" so reports can still render
                schedule = DeviceActivitySchedule(
                    intervalStart: DateComponents(hour: 0, minute: 0),
                    intervalEnd: DateComponents(hour: 23, minute: 59),
                    repeats: true
                )
            }

            // Keep identifiers aligned with those used in the report extension.
            let names: [DeviceActivityName] = [
                .home, .totalActivity, .widget, .moreInsights, .topApps, .totalPickups
            ]

            // Stop existing and restart with fresh schedule
            stopAllMonitoring()

            for name in names {
                do {
                    try await center.startMonitoring(name, during: schedule)
                } catch {
                    // Non-fatal; continue with others
                    // You could log this error if needed
                    print("Failed to start monitoring for \(name): \(error)")
                }
            }
        }
    }

    func stopAllMonitoring() {
        Task {
            let names: [DeviceActivityName] = [
                .home, .totalActivity, .widget, .moreInsights, .topApps, .totalPickups
            ]
            
            // Option 1: Stop all at once
            await center.stopMonitoring(names)
            
            // Option 2: Stop each individually (alternative approach)
            // for name in names {
            //     await center.stopMonitoring([name])
            // }
        }
    }

    // Helpers

    private func scheduleRangeForToday(startMinutes: Int, endMinutes: Int) -> DateInterval {
        // Compute today's interval respecting crossing midnight.
        let now = Date()
        let startDate = date(on: now, minutes: startMinutes)
        let endDate = date(on: now, minutes: endMinutes)

        if startDate < endDate {
            return DateInterval(start: startDate, end: endDate)
        } else {
            // Crosses midnight: for reporting use a single interval that ends tomorrow at end time
            let endTomorrow = date(on: calendar.date(byAdding: .day, value: 1, to: now) ?? now, minutes: endMinutes)
            return DateInterval(start: startDate, end: endTomorrow)
        }
    }

    private func date(on base: Date, minutes: Int) -> Date {
        let hour = minutes / 60
        let min = minutes % 60
        return calendar.date(
            bySettingHour: hour,
            minute: min,
            second: 0,
            of: base
        ) ?? base
    }

    private func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func endOfDay(_ date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
