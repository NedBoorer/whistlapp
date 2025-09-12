//
//  FocusScheduleViewModel.swift
//  whistl
//
//  Created by Ned Boorer on 11/9/2025.
//

import Foundation
import SwiftUI
import FamilyControls
import ManagedSettings
import Observation

// MARK: - Weekly schedule types (local to this file to avoid cross-file breakage)

enum Weekday: Int, CaseIterable, Codable {
    // Align with Calendar weekday: 1=Sunday ... 7=Saturday
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    static func today(calendar: Calendar = .current) -> Weekday {
        let wd = calendar.component(.weekday, from: Date())
        return Weekday(rawValue: wd) ?? .sunday
    }
}

struct TimeRange: Codable, Equatable {
    var startMinutes: Int // minutes since midnight
    var endMinutes: Int   // minutes since midnight

    // Utility: does a given date fall within this range (supports overnight crossing)
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        isNowInsideWindow(now: date, startMinutes: startMinutes, endMinutes: endMinutes, calendar: calendar)
    }
}

struct DaySchedule: Codable, Equatable {
    var weekdayRaw: Int         // store as Int for stable coding
    var enabled: Bool
    var ranges: [TimeRange]

    var weekday: Weekday {
        get { Weekday(rawValue: weekdayRaw) ?? .sunday }
        set { weekdayRaw = newValue.rawValue }
    }

    init(weekday: Weekday, enabled: Bool = true, ranges: [TimeRange] = []) {
        self.weekdayRaw = weekday.rawValue
        self.enabled = enabled
        self.ranges = ranges
    }
}

struct WeeklyBlockPlan: Codable, Equatable {
    var days: [DaySchedule]

    static func empty() -> WeeklyBlockPlan {
        WeeklyBlockPlan(days: Weekday.allCases.map { DaySchedule(weekday: $0, enabled: false, ranges: []) })
    }

    static func replicated(startMinutes: Int, endMinutes: Int) -> WeeklyBlockPlan {
        let tr = TimeRange(startMinutes: startMinutes, endMinutes: endMinutes)
        return WeeklyBlockPlan(days: Weekday.allCases.map { DaySchedule(weekday: $0, enabled: true, ranges: [tr]) })
    }

    func day(for weekday: Weekday) -> DaySchedule? {
        days.first(where: { $0.weekday == weekday })
    }

    func index(for weekday: Weekday) -> Int? {
        days.firstIndex(where: { $0.weekday == weekday })
    }
}

// MARK: - ViewModel

@Observable
final class FocusScheduleViewModel {
    // Public state
    var isAuthorized: Bool = false

    // Weekly plan (multiple ranges per day)
    var weeklyPlan: WeeklyBlockPlan = .empty()

    // Global enable for schedule logic (keeps your original toggle semantics)
    var isScheduleEnabled: Bool = false

    // Global selection (applies to all days/ranges)
    var selection: FamilyActivitySelection = FamilyActivitySelection()

    // Live shield state
    var isShieldActive: Bool = false
    var lastStatusMessage: String = ""

    // Manual override: when true, block immediately regardless of schedule windows
    var isManualBlockActive: Bool = false

    // Pause/break state
    var isPaused: Bool = false
    var pauseUntil: Date? = nil

    // Internals
    private let store = ManagedSettingsStore()
    private var timer: Timer?
    private var scenePhaseObservation: NSObjectProtocol?
    private var pauseTimer: Timer?
    private let calendar = Calendar.current

    // Shared storage keys for weekly plan (kept here to avoid breaking SharedConfig.swift)
    private let weeklyPlanKey = "fc_weeklyPlan_v1"

    init() {
        // Load persisted config first so UI reflects current shared state
        loadFromShared()

        Task { @MainActor in
            await refreshAuthorization()
        }
        startScheduler()
        observeScenePhase()

        // Keep DeviceActivityCenter reporting in sync
        ReportingScheduler.shared.refreshMonitoringFromShared()
    }

    deinit {
        stopScheduler()
        stopPauseTimer()
        if let obs = scenePhaseObservation {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Authorization

    @MainActor
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            await refreshAuthorization()
        } catch {
            lastStatusMessage = "Authorization failed: \((error as NSError).localizedDescription)"
            isAuthorized = false
            SharedConfigStore.save(isAuthorized: false)
            notifyExtension()
            ReportingScheduler.shared.stopAllMonitoring()
        }
    }

    @MainActor
    func refreshAuthorization() async {
        let status = AuthorizationCenter.shared.authorizationStatus
        switch status {
        case .approved:
            isAuthorized = true
            lastStatusMessage = "Screen Time access approved."
        case .notDetermined:
            isAuthorized = false
            lastStatusMessage = "Screen Time access not determined."
        case .denied:
            isAuthorized = false
            lastStatusMessage = "Screen Time access denied."
        @unknown default:
            isAuthorized = false
            lastStatusMessage = "Unknown authorization state."
        }
        SharedConfigStore.save(isAuthorized: isAuthorized)
        notifyExtension()
        evaluateAndApplyShield()

        if isAuthorized {
            ReportingScheduler.shared.refreshMonitoringFromShared()
        } else {
            ReportingScheduler.shared.stopAllMonitoring()
        }
    }

    // MARK: - Schedule changes (weekly)

    func setScheduleEnabled(_ enabled: Bool) {
        isScheduleEnabled = enabled
        SharedConfigStore.save(isScheduleEnabled: enabled)
        notifyExtension()
        evaluateAndApplyShield()
        ReportingScheduler.shared.refreshMonitoringFromShared()
    }

    // Add a new range for a given weekday (default 21:00–07:00)
    func addRange(for weekday: Weekday, startMinutes: Int = 21*60, endMinutes: Int = 7*60) {
        var plan = weeklyPlan
        if let idx = plan.index(for: weekday) {
            plan.days[idx].enabled = true
            plan.days[idx].ranges.append(TimeRange(startMinutes: startMinutes, endMinutes: endMinutes))
            weeklyPlan = plan
            persistWeeklyPlan()
            notifyExtension()
            evaluateAndApplyShield()
            ReportingScheduler.shared.refreshMonitoringFromShared()
        }
    }

    func updateRange(for weekday: Weekday, at index: Int, startMinutes: Int, endMinutes: Int) {
        guard let dayIndex = weeklyPlan.index(for: weekday), weeklyPlan.days[dayIndex].ranges.indices.contains(index) else { return }
        weeklyPlan.days[dayIndex].ranges[index] = TimeRange(startMinutes: startMinutes, endMinutes: endMinutes)
        persistWeeklyPlan()
        notifyExtension()
        evaluateAndApplyShield()
        ReportingScheduler.shared.refreshMonitoringFromShared()
    }

    func removeRanges(for weekday: Weekday, at offsets: IndexSet) {
        guard let dayIndex = weeklyPlan.index(for: weekday) else { return }
        weeklyPlan.days[dayIndex].ranges.remove(atOffsets: offsets)
        persistWeeklyPlan()
        notifyExtension()
        evaluateAndApplyShield()
        ReportingScheduler.shared.refreshMonitoringFromShared()
    }

    func setDayEnabled(_ weekday: Weekday, enabled: Bool) {
        guard let dayIndex = weeklyPlan.index(for: weekday) else { return }
        weeklyPlan.days[dayIndex].enabled = enabled
        persistWeeklyPlan()
        notifyExtension()
        evaluateAndApplyShield()
        ReportingScheduler.shared.refreshMonitoringFromShared()
    }

    // MARK: - Selection changes (global)

    func updateSelection(_ newSelection: FamilyActivitySelection) {
        selection = newSelection
        SharedConfigStore.save(selection: newSelection)
        notifyExtension()
        evaluateAndApplyShield()
        ReportingScheduler.shared.refreshMonitoringFromShared()
    }

    // MARK: - Manual controls

    func activateManualBlock() {
        isManualBlockActive = true
        SharedConfigStore.save(isManualBlockActive: true)
        notifyExtension()
        evaluateAndApplyShield()
        ReportingScheduler.shared.refreshMonitoringFromShared()
    }

    func deactivateManualBlock() {
        isManualBlockActive = false
        SharedConfigStore.save(isManualBlockActive: false)
        notifyExtension()
        evaluateAndApplyShield()
        ReportingScheduler.shared.refreshMonitoringFromShared()
    }

    // MARK: - 5-minute break (pause)

    func startFiveMinuteBreak(now: Date = Date()) {
        let until = now.addingTimeInterval(5 * 60)
        pauseUntil = until
        isPaused = true
        SharedConfigStore.savePause(until: until)
        // Clear shields immediately
        clearShield()
        lastStatusMessage = "Break active for 5 minutes."
        notifyExtension()
        // Keep evaluating so we auto-resume
        startPauseTimer()
    }

    func cancelBreak() {
        // End pause immediately
        pauseUntil = nil
        isPaused = false
        SharedConfigStore.savePause(until: nil)
        stopPauseTimer()
        // Notify others first (so any background component can resume too)
        notifyExtension()
        // Re-evaluate and apply shields right away on main thread
        if Thread.isMainThread {
            evaluateAndApplyShield()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.evaluateAndApplyShield()
            }
        }
    }

    private func startPauseTimer() {
        stopPauseTimer()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tickPause()
        }
        // also do an immediate tick to ensure state is consistent
        tickPause()
    }

    private func stopPauseTimer() {
        pauseTimer?.invalidate()
        pauseTimer = nil
    }

    private func tickPause(now: Date = Date()) {
        // Sync from shared in case another process updated it
        let sharedUntil = SharedConfigStore.loadPauseUntil()
        pauseUntil = sharedUntil
        isPaused = SharedConfigStore.isPaused(now: now)
        if isPaused {
            // Ensure shield stays cleared during pause
            clearShield()
        } else {
            // Pause expired; clean up and re-evaluate
            if sharedUntil != nil {
                SharedConfigStore.savePause(until: nil)
                notifyExtension()
            }
            stopPauseTimer()
            evaluateAndApplyShield()
        }
    }

    // MARK: - Enforcement (in-app reflection; extension is authoritative in background)

    func evaluateAndApplyShield() {
        // Honor pause first
        isPaused = SharedConfigStore.isPaused()
        pauseUntil = SharedConfigStore.loadPauseUntil()
        if isPaused {
            clearShield()
            lastStatusMessage = "On a short break."
            return
        }

        guard isAuthorized else { clearShield(); return }

        if isManualBlockActive {
            applyShield()
            return
        }

        guard isScheduleEnabled else { clearShield(); return }

        let now = Date()
        let today = Weekday.today(calendar: calendar)
        guard let day = weeklyPlan.day(for: today), day.enabled else {
            clearShield()
            return
        }

        let insideAny = day.ranges.contains { $0.contains(now, calendar: calendar) }
        if insideAny {
            applyShield()
        } else {
            clearShield()
        }
    }

    private func applyShield() {
        // Applications: direct tokens or nil
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens

        // Categories: wrap tokens in policy type
        if selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = nil
        } else {
            store.shield.applicationCategories = .specific(selection.categoryTokens)
        }

        isShieldActive = (store.shield.applications != nil) || (store.shield.applicationCategories != nil)
        if isShieldActive {
            lastStatusMessage = isManualBlockActive ? "Blocking active (manual)." : "Blocking active (scheduled)."
            AnalyticsStore.markShieldActivated()
        } else {
            lastStatusMessage = "No items selected to block."
        }
    }

    func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        if isShieldActive {
            AnalyticsStore.markShieldDeactivated()
        }
        isShieldActive = false
        // Keep lastStatusMessage set by caller to reflect pause vs. inactive
        if !isPaused {
            lastStatusMessage = "Blocking inactive."
        }
    }

    // MARK: - Foreground scheduler (UI reflection only)

    private func startScheduler() {
        stopScheduler()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.evaluateAndApplyShield()
            self?.tickPause()
        }
        evaluateAndApplyShield()
        tickPause()
    }

    private func stopScheduler() {
        timer?.invalidate()
        timer = nil
    }

    private func observeScenePhase() {
        scenePhaseObservation = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadFromShared()
            self?.evaluateAndApplyShield()
            self?.tickPause()
            ReportingScheduler.shared.refreshMonitoringFromShared()
        }
    }

    // MARK: - Legacy bridge (optional helpers for external callers)

    // Import a single daily window into all days (legacy)
    func importLegacyBlock(startMinutes: Int, endMinutes: Int) {
        weeklyPlan = .replicated(startMinutes: startMinutes, endMinutes: endMinutes)
        persistWeeklyPlan()
        notifyExtension()
        evaluateAndApplyShield()
        ReportingScheduler.shared.refreshMonitoringFromShared()
    }

    // MARK: - Shared persistence

    private func persistWeeklyPlan() {
        do {
            let data = try JSONEncoder().encode(weeklyPlan)
            SharedConfigStore.defaults.set(data, forKey: weeklyPlanKey)
        } catch {
            // Best-effort; keep in-memory state even if persistence fails
        }
        // Also persist a “current window” summary for any legacy consumers (first enabled day’s first range or fallback)
        // Choose today’s first range if available, else any enabled day’s first range
        if let summary = firstRangeSummaryForTodayOrAny() {
            SharedConfigStore.save(startMinutes: summary.startMinutes, endMinutes: summary.endMinutes)
        }
    }

    private func loadWeeklyPlan() -> WeeklyBlockPlan? {
        guard let data = SharedConfigStore.defaults.data(forKey: weeklyPlanKey) else { return nil }
        return try? JSONDecoder().decode(WeeklyBlockPlan.self, from: data)
    }

    private func migrateFromLegacyIfNeeded() {
        // If no weekly plan exists, derive it from legacy single window keys
        if loadWeeklyPlan() == nil {
            let start = SharedConfigStore.loadStartMinutes()
            let end   = SharedConfigStore.loadEndMinutes()
            weeklyPlan = .replicated(startMinutes: start, endMinutes: end)
            persistWeeklyPlan()
        }
    }

    private func firstRangeSummaryForTodayOrAny() -> TimeRange? {
        let today = Weekday.today(calendar: calendar)
        if let day = weeklyPlan.day(for: today), day.enabled, let first = day.ranges.first {
            return first
        }
        for d in weeklyPlan.days where d.enabled {
            if let first = d.ranges.first { return first }
        }
        return nil
    }

    private func loadFromShared() {
        // Selection
        let sharedSel = SharedConfigStore.loadSelection()
        if !sharedSel.applicationTokens.isEmpty || !sharedSel.categoryTokens.isEmpty {
            self.selection = sharedSel
        }

        // Flags
        self.isScheduleEnabled = SharedConfigStore.loadIsScheduleEnabled()
        self.isManualBlockActive = SharedConfigStore.loadIsManualBlockActive()
        self.isAuthorized = SharedConfigStore.loadIsAuthorized()

        // Pause
        self.pauseUntil = SharedConfigStore.loadPauseUntil()
        self.isPaused = SharedConfigStore.isPaused()

        // Weekly plan (with migration from legacy)
        if let plan = loadWeeklyPlan() {
            self.weeklyPlan = plan
        } else {
            migrateFromLegacyIfNeeded()
        }
    }

    private func notifyExtension() {
        postConfigDidChangeDarwinNotification()
    }
}
