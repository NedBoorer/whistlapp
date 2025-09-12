//
//  ReportingScheduler.swift
//  whistl
//
//  Created by Assistant on 11/9/2025.
//

import Foundation
import DeviceActivity
import FamilyControls

/// Centralizes DeviceActivityCenter monitoring so the report extension receives data
/// filtered by the user's selection and within the configured daily window.
final class ReportingScheduler {

    static let shared = ReportingScheduler()

    private let center = DeviceActivityCenter()

    private init() { }

    func stopAllMonitoring() {
        for context in ReportingContext.allCases {
            center.stopMonitoring(context)
        }
    }

    /// Refresh monitoring from the shared config persisted by FocusScheduleViewModel.
    /// Safe to call frequently; will stop/restart as needed.
    func refreshMonitoringFromShared(now: Date = Date(), calendar: Calendar = .current) {
        // Authorization is required to monitor. If not authorized, stop and bail.
        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            stopAllMonitoring()
            return
        }

        let selection = SharedConfigStore.loadSelection()
        let isScheduleEnabled = SharedConfigStore.loadIsScheduleEnabled()
        let start = SharedConfigStore.loadStartMinutes()
        let end = SharedConfigStore.loadEndMinutes()

        // Build schedule (if disabled, monitor "always today" so reports can still show activity)
        let schedule: DeviceActivitySchedule
        if isScheduleEnabled {
            schedule = Self.schedule(fromStartMinutes: start, endMinutes: end, calendar: calendar)
        } else {
            // Fallback: monitor for the whole day so reports still populate
            schedule = Self.wholeDaySchedule(calendar: calendar)
        }

        let filter = DeviceActivityFilter(
            segment: .daily(during: schedule),
            categories: selection.categoryTokens.isEmpty ? nil : selection.categoryTokens,
            applications: selection.applicationTokens.isEmpty ? nil : selection.applicationTokens,
            webDomains: nil
        )

        // Start monitoring all contexts you want reports for
        for context in ReportingContext.allCases {
            do {
                try center.startMonitoring(context, during: schedule, with: filter)
            } catch {
                // Best-effort: continue trying other contexts
                // In production, you might log this.
            }
        }
    }

    private static func wholeDaySchedule(calendar: Calendar) -> DeviceActivitySchedule {
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? startOfDay
        let startComponents = calendar.dateComponents([.hour, .minute], from: startOfDay)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endOfDay)

        return DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: true
        )
    }

    private static func schedule(fromStartMinutes start: Int, endMinutes end: Int, calendar: Calendar) -> DeviceActivitySchedule {
        let startHour = start / 60
        let startMin  = start % 60
        let endHour   = end / 60
        let endMin    = end % 60

        let startComps = DateComponents(hour: startHour, minute: startMin)
        let endComps   = DateComponents(hour: endHour, minute: endMin)

        return DeviceActivitySchedule(
            intervalStart: startComps,
            intervalEnd: endComps,
            repeats: true
        )
    }
}

/// Contexts used to route DeviceActivityResults to the appropriate scenes.
/// Shared between the app (for scheduling) and the extension (for scenes).
enum ReportingContext: String, CaseIterable, DeviceActivityReportContext {
    case home
    case totalActivity
    case topApps
    case totalPickups
    case moreInsights
    case widget
}

