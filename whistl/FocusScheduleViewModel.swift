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
import FirebaseAuth
import FirebaseFirestore

// MARK: - Weekly schedule types (local to this file to avoid cross-file breakage)

enum Weekday: Int, CaseIterable, Codable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    static func today(calendar: Calendar = .current) -> Weekday {
        let wd = calendar.component(.weekday, from: Date())
        return Weekday(rawValue: wd) ?? .sunday
    }
}

struct TimeRange: Codable, Equatable {
    var startMinutes: Int
    var endMinutes: Int

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        isNowInsideWindow(now: date, startMinutes: startMinutes, endMinutes: endMinutes, calendar: calendar)
    }
}

struct DaySchedule: Codable, Equatable {
    var weekdayRaw: Int
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

    // Global enable for schedule logic
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

    // Break request state
    var isMyBreakRequestPending: Bool = false         // my outgoing request to partner
    var hasPendingPartnerRequest: Bool = false        // incoming request from partner
    var lastBreakRequestError: String? = nil

    // Pair/partner context (injected)
    var pairId: String? = nil
    var myUID: String? = Auth.auth().currentUser?.uid
    var partnerUID: String? = nil

    // Internals
    private let store = ManagedSettingsStore()
    private var timer: Timer?
    private var scenePhaseObservation: NSObjectProtocol?
    private var pauseTimer: Timer?
    private let calendar = Calendar.current
    private var policyListener: ListenerRegistration?
    private var myRequestListener: ListenerRegistration?
    private var partnerRequestListener: ListenerRegistration?

    private let db = Firestore.firestore()

    // Shared storage keys for weekly plan
    private let weeklyPlanKey = "fc_weeklyPlan_v1"

    init() {
        loadFromShared()

        Task { @MainActor in
            await refreshAuthorization()
        }
        startScheduler()
        observeScenePhase()

        // Sync reporting
        ReportingScheduler.shared.refreshMonitoringFromShared()

        // Attach listeners if we have enough context
        attachPolicyListenerIfPossible()
        attachBreakRequestListenersIfPossible()
    }

    deinit {
        stopScheduler()
        stopPauseTimer()
        policyListener?.remove()
        policyListener = nil
        myRequestListener?.remove()
        myRequestListener = nil
        partnerRequestListener?.remove()
        partnerRequestListener = nil
        if let obs = scenePhaseObservation {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Inject pairing context

    func updatePairContext(pairId: String?, myUID: String?, partnerUID: String?) {
        self.pairId = pairId
        self.myUID = myUID
        self.partnerUID = partnerUID
        attachPolicyListenerIfPossible()
        attachBreakRequestListenersIfPossible()
    }

    private func attachPolicyListenerIfPossible() {
        policyListener?.remove()
        policyListener = nil
        guard let pid = pairId, let owner = myUID, !pid.isEmpty, !owner.isEmpty else { return }
        let ref = db.collection("pairSpaces").document(pid).collection("devicePolicies").document(owner)
        policyListener = ref.addSnapshotListener { [weak self] snap, _ in
            guard let self else { return }
            guard let data = snap?.data() else { return }
            if let ts = data["pauseUntil"] as? Timestamp {
                SharedConfigStore.savePause(until: ts.dateValue())
            } else {
                SharedConfigStore.savePause(until: nil)
            }
            self.pauseUntil = SharedConfigStore.loadPauseUntil()
            self.isPaused = SharedConfigStore.isPaused()
            self.evaluateAndApplyShield()
        }
    }

    private func attachBreakRequestListenersIfPossible() {
        // Clean up existing
        myRequestListener?.remove()
        myRequestListener = nil
        partnerRequestListener?.remove()
        partnerRequestListener = nil

        guard let pid = pairId, !pid.isEmpty else { return }

        // Listen to my outgoing request (ownerUID = myUID)
        if let owner = myUID, !owner.isEmpty {
            let myRef = db.collection("pairSpaces").document(pid).collection("breakRequests").document(owner)
            myRequestListener = myRef.addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                guard let data = snap?.data() else {
                    self.isMyBreakRequestPending = false
                    return
                }
                let status = (data["status"] as? String) ?? "pending"
                self.isMyBreakRequestPending = (status == "pending")
                // If partner approved and pauseUntil has been written by partner policy listener, no action here.
            }
        }

        // Listen to partner's incoming request (ownerUID = partnerUID)
        if let partner = partnerUID, !partner.isEmpty {
            let partnerRef = db.collection("pairSpaces").document(pid).collection("breakRequests").document(partner)
            var lastSeenRequestedAt: Date? = nil
            partnerRequestListener = partnerRef.addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                guard let data = snap?.data() else {
                    self.hasPendingPartnerRequest = false
                    return
                }
                let status = (data["status"] as? String) ?? "pending"
                self.hasPendingPartnerRequest = (status == "pending")

                // Ping partner device when a fresh pending request arrives
                if status == "pending", let ts = data["requestedAt"] as? Timestamp {
                    let requestedAt = ts.dateValue()
                    if lastSeenRequestedAt == nil || requestedAt > (lastSeenRequestedAt ?? .distantPast) {
                        lastSeenRequestedAt = requestedAt
                        WhistlNotifier.scheduleAttemptNotification(
                            title: "Break request",
                            body: "Your partner requested a 5‑minute break."
                        )
                    }
                }
            }
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

    // MARK: - Break control (partner-granted + request/approve)

    // Local device cannot grant its own break.
    func startFiveMinuteBreak(now: Date = Date()) {
        // Intentionally no-op to enforce partner-only grants.
    }

    // Owner may cancel an active break on their device (policy choice).
    func cancelBreak() {
        pauseUntil = nil
        isPaused = false
        SharedConfigStore.savePause(until: nil)
        stopPauseTimer()
        notifyExtension()
        if Thread.isMainThread {
            evaluateAndApplyShield()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.evaluateAndApplyShield()
            }
        }
        // Clear pause in Firestore so partner sees it end early
        Task { await writePauseUntil(nil, forOwner: myUID) }
    }

    // Partner grants a break to the other device.
    func grantFiveMinuteBreakToPartner(now: Date = Date()) async {
        guard let _ = pairId, let target = partnerUID else { return }
        let until = now.addingTimeInterval(5 * 60)
        await writePauseUntil(until, forOwner: target)
        // Also mark the request approved if one exists
        await approvePartnerBreakRequest()
    }

    private func writePauseUntil(_ until: Date?, forOwner ownerUID: String?) async {
        guard let pid = pairId, let owner = ownerUID, !pid.isEmpty, !owner.isEmpty else { return }
        let ref = db.collection("pairSpaces").document(pid).collection("devicePolicies").document(owner)
        var data: [String: Any] = [:]
        if let until {
            data["pauseUntil"] = Timestamp(date: until)
        } else {
            data["pauseUntil"] = FieldValue.delete()
        }
        data["updatedAt"] = FieldValue.serverTimestamp()
        if let me = Auth.auth().currentUser?.uid {
            data["updatedBy"] = me
        }
        do {
            try await ref.setData(data, merge: true)
        } catch {
            // ignore for now
        }
    }

    // Owner requests a 5-minute break (creates/updates a pending request)
    func requestBreak() async {
        guard let pid = pairId, let owner = myUID, !pid.isEmpty, !owner.isEmpty else { return }
        let ref = db.collection("pairSpaces").document(pid).collection("breakRequests").document(owner)
        do {
            try await ref.setData([
                "status": "pending",
                "requestedAt": FieldValue.serverTimestamp(),
                "requestedBy": owner
            ], merge: true)
            await MainActor.run {
                self.isMyBreakRequestPending = true
                self.lastBreakRequestError = nil
            }
        } catch {
            await MainActor.run {
                self.lastBreakRequestError = (error as NSError).localizedDescription
            }
        }
    }

    // Owner cancels their pending request
    func cancelBreakRequest() async {
        guard let pid = pairId, let owner = myUID, !pid.isEmpty, !owner.isEmpty else { return }
        let ref = db.collection("pairSpaces").document(pid).collection("breakRequests").document(owner)
        do {
            try await ref.delete()
            await MainActor.run {
                self.isMyBreakRequestPending = false
                self.lastBreakRequestError = nil
            }
        } catch {
            await MainActor.run {
                self.lastBreakRequestError = (error as NSError).localizedDescription
            }
        }
    }

    // Partner approves the incoming request (and grants pause)
    func approvePartnerBreakRequest() async {
        guard let pid = pairId, let target = partnerUID, !pid.isEmpty, !target.isEmpty else { return }
        let reqRef = db.collection("pairSpaces").document(pid).collection("breakRequests").document(target)
        do {
            try await reqRef.setData([
                "status": "approved",
                "approvedAt": FieldValue.serverTimestamp(),
                "approvedBy": Auth.auth().currentUser?.uid ?? ""
            ], merge: true)
        } catch {
            // ignore for now
        }
    }

    // Partner rejects the incoming request
    func rejectPartnerBreakRequest() async {
        guard let pid = pairId, let target = partnerUID, !pid.isEmpty, !target.isEmpty else { return }
        let reqRef = db.collection("pairSpaces").document(pid).collection("breakRequests").document(target)
        do {
            try await reqRef.setData([
                "status": "rejected",
                "approvedAt": FieldValue.serverTimestamp(),
                "approvedBy": Auth.auth().currentUser?.uid ?? ""
            ], merge: true)
            await MainActor.run {
                self.hasPendingPartnerRequest = false
            }
        } catch {
            // ignore for now
        }
    }

    private func startPauseTimer() {
        stopPauseTimer()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tickPause()
        }
        tickPause()
    }

    private func stopPauseTimer() {
        pauseTimer?.invalidate()
        pauseTimer = nil
    }

    private func tickPause(now: Date = Date()) {
        let sharedUntil = SharedConfigStore.loadPauseUntil()
        pauseUntil = sharedUntil
        isPaused = SharedConfigStore.isPaused(now: now)
        if isPaused {
            clearShield()
        } else {
            if sharedUntil != nil {
                SharedConfigStore.savePause(until: nil)
                notifyExtension()
            }
            stopPauseTimer()
            evaluateAndApplyShield()
        }
    }

    // MARK: - Enforcement

    func evaluateAndApplyShield() {
        // Honor pause first (pause is authoritative from Firestore)
        isPaused = SharedConfigStore.isPaused()
        pauseUntil = SharedConfigStore.loadPauseUntil()
        if isPaused {
            clearShield()
            lastStatusMessage = "On a short break."
            startPauseTimer()
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
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens

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
        if !isPaused {
            lastStatusMessage = "Blocking inactive."
        }
    }

    // MARK: - Foreground scheduler

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

    // MARK: - Legacy bridge

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
        } catch { }
        if let summary = firstRangeSummaryForTodayOrAny() {
            SharedConfigStore.save(startMinutes: summary.startMinutes, endMinutes: summary.endMinutes)
        }
    }

    private func loadWeeklyPlan() -> WeeklyBlockPlan? {
        guard let data = SharedConfigStore.defaults.data(forKey: weeklyPlanKey) else { return nil }
        return try? JSONDecoder().decode(WeeklyBlockPlan.self, from: data)
    }

    private func migrateFromLegacyIfNeeded() {
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
        let sharedSel = SharedConfigStore.loadSelection()
        if !sharedSel.applicationTokens.isEmpty || !sharedSel.categoryTokens.isEmpty {
            self.selection = sharedSel
        }

        self.isScheduleEnabled = SharedConfigStore.loadIsScheduleEnabled()
        self.isManualBlockActive = SharedConfigStore.loadIsManualBlockActive()
        self.isAuthorized = SharedConfigStore.loadIsAuthorized()

        self.pauseUntil = SharedConfigStore.loadPauseUntil()
        self.isPaused = SharedConfigStore.isPaused()

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

