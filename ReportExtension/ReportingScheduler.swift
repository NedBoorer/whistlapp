//
//  ReportingScheduler.swift
//  whistl
//
//  Created by Ned Boorer on 12/9/2025.
//

import Foundation
import DeviceActivity
import FamilyControls

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

            // Build filter
            let filter = DeviceActivityFilter(
                segment: .daily(
                    during: scheduleRangeForToday(startMinutes: start, endMinutes: end)
                ),
                categories: selection.categoryTokens.isEmpty ? nil : selection.categoryTokens,
                applications: selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            )

            // If schedule disabled, monitor "today all day" so reports can still render
            let fallbackFilter = DeviceActivityFilter(
                segment: .daily(during: DateInterval(start: startOfDay(Date()), end: endOfDay(Date()))),
                categories: selection.categoryTokens.isEmpty ? nil : selection.categoryTokens,
                applications: selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            )

            // Start monitoring for all contexts we support.
            // You can choose a subset if you want different windows, but here we keep them aligned.
            let contexts: [DeviceActivityReport.Context] = [
                .home, .totalActivity, .widget, .moreInsights, .topApps, .totalPickups
            ]

            // Stop existing and restart with fresh filters
            stopAllMonitoring()

            for ctx in contexts {
                do {
                    try await center.startMonitoring(
                        ctx,
                        during: isScheduleEnabled ? filter : fallbackFilter
                    )
                } catch {
                    // Non-fatal; continue with others
                    // You could log this error if needed
                }
            }
        }
    }

    func stopAllMonitoring() {
        Task {
            let contexts: [DeviceActivityReport.Context] = [
                .home, .totalActivity, .widget, .moreInsights, .topApps, .totalPickups
            ]
            for ctx in contexts {
                await center.stopMonitoring(ctx)
            }
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
            // Crosses midnight: split; for reporting we’ll use a single interval that ends tomorrow at end time
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

