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

@Observable
final class FocusScheduleViewModel {
    // Public state
    var isAuthorized: Bool = false
    var isScheduleEnabled: Bool = false
    var selection: FamilyActivitySelection = FamilyActivitySelection()
    var startComponents: DateComponents = DateComponents(hour: 21, minute: 0) // default 9pm
    var endComponents: DateComponents = DateComponents(hour: 7, minute: 0)    // default 7am
    var isShieldActive: Bool = false
    var lastStatusMessage: String = ""

    // Manual override: when true, block immediately regardless of time window
    var isManualBlockActive: Bool = false

    // Optional: set from your shared flow when available
    var approvedBlockSchedule: BlockSchedule? {
        didSet {
            if let sch = approvedBlockSchedule {
                startComponents = DateComponents(hour: sch.startMinutes / 60, minute: sch.startMinutes % 60)
                endComponents   = DateComponents(hour: sch.endMinutes / 60, minute: sch.endMinutes % 60)
                persistScheduleToShared()
                notifyExtension()
                evaluateAndApplyShield()
            }
        }
    }

    // Internals
    private let store = ManagedSettingsStore()
    private var timer: Timer?
    private var scenePhaseObservation: NSObjectProtocol?

    init() {
        // Load persisted config first so UI reflects current shared state
        loadFromShared()

        Task { @MainActor in
            await refreshAuthorization()
        }
        startScheduler()
        observeScenePhase()
    }

    deinit {
        stopScheduler()
        if let obs = scenePhaseObservation {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // Authorization
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
    }

    // Schedule changes
    func setScheduleEnabled(_ enabled: Bool) {
        isScheduleEnabled = enabled
        SharedConfigStore.save(isScheduleEnabled: enabled)
        notifyExtension()
        evaluateAndApplyShield()
    }

    func updateStart(_ comps: DateComponents) {
        startComponents = comps
        persistScheduleToShared()
        notifyExtension()
        evaluateAndApplyShield()
    }

    func updateEnd(_ comps: DateComponents) {
        endComponents = comps
        persistScheduleToShared()
        notifyExtension()
        evaluateAndApplyShield()
    }

    func updateSelection(_ newSelection: FamilyActivitySelection) {
        selection = newSelection
        SharedConfigStore.save(selection: newSelection)
        notifyExtension()
        evaluateAndApplyShield()
    }

    // Manual controls
    func activateManualBlock() {
        isManualBlockActive = true
        SharedConfigStore.save(isManualBlockActive: true)
        notifyExtension()
        evaluateAndApplyShield()
    }

    func deactivateManualBlock() {
        isManualBlockActive = false
        SharedConfigStore.save(isManualBlockActive: false)
        notifyExtension()
        evaluateAndApplyShield()
    }

    // Enforcement (in-app reflection; extension is authoritative in background)
    func evaluateAndApplyShield() {
        guard isAuthorized else { clearShield(); return }

        if isManualBlockActive {
            applyShield()
            return
        }

        guard isScheduleEnabled else { clearShield(); return }

        let start = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let end   = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)
        if isNowInsideWindow(now: Date(), startMinutes: start, endMinutes: end) {
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
        } else {
            lastStatusMessage = "No items selected to block."
        }
    }

    func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        isShieldActive = false
        lastStatusMessage = "Blocking inactive."
    }

    // Foreground scheduler (UI reflection only)
    private func startScheduler() {
        stopScheduler()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.evaluateAndApplyShield()
        }
        evaluateAndApplyShield()
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
        }
    }

    // Bridge with your BlockSchedule
    func importBlockSchedule(_ schedule: BlockSchedule) {
        startComponents = DateComponents(hour: schedule.startMinutes / 60, minute: schedule.startMinutes % 60)
        endComponents   = DateComponents(hour: schedule.endMinutes / 60, minute: schedule.endMinutes % 60)
        persistScheduleToShared()
        notifyExtension()
        evaluateAndApplyShield()
    }

    func exportBlockSchedule() -> BlockSchedule {
        let start = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let end   = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)
        return BlockSchedule(startMinutes: start, endMinutes: end)
    }

    // MARK: - Shared persistence

    private func persistScheduleToShared() {
        let start = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let end   = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)
        SharedConfigStore.save(startMinutes: start, endMinutes: end)
    }

    private func loadFromShared() {
        // Pull persisted values to reflect current config
        let sharedSel = SharedConfigStore.loadSelection()
        if !sharedSel.applicationTokens.isEmpty || !sharedSel.categoryTokens.isEmpty {
            self.selection = sharedSel
        }
        self.isScheduleEnabled = SharedConfigStore.loadIsScheduleEnabled()
        self.isManualBlockActive = SharedConfigStore.loadIsManualBlockActive()

        let start = SharedConfigStore.loadStartMinutes()
        let end   = SharedConfigStore.loadEndMinutes()
        self.startComponents = DateComponents(hour: start / 60, minute: start % 60)
        self.endComponents   = DateComponents(hour: end / 60, minute: end % 60)
        self.isAuthorized = SharedConfigStore.loadIsAuthorized()
    }

    private func notifyExtension() {
        postConfigDidChangeDarwinNotification()
    }
}

