//
//  ShieldDataSourceAndEnforcer.swift
//  shieldwhistl
//
//  Created by Ned Boorer on 11/9/2025.
//

import Foundation
import ManagedSettings
import FamilyControls
import UIKit

// MARK: - Shield UI

class ShieldDataSource: ShieldConfigurationDataSource {

    private let enforcer = EnforcementController()

    override init() {
        super.init()
        enforcer.start()
    }

    override func configuration(shielding application: ApplicationToken) -> ShieldConfiguration {
        return defaultConfig()
    }

    override func configuration(shielding applicationCategory: ActivityCategoryToken) -> ShieldConfiguration {
        return defaultConfig()
    }

    override func configuration(shielding webDomain: WebDomainToken) -> ShieldConfiguration {
        return defaultConfig()
    }

    override func configuration(shielding application: ApplicationToken, in category: ActivityCategoryToken) -> ShieldConfiguration {
        return defaultConfig()
    }

    private func defaultConfig() -> ShieldConfiguration {
        var config = ShieldConfiguration()
        config.title = "Stay on track"
        config.subtitle = "This app is blocked right now."
        config.primaryButtonLabel = "Close"
        config.secondaryButtonLabel = "Ask later"
        return config
    }
}

// MARK: - Enforcement Controller

final class EnforcementController {
    private let store = ManagedSettingsStore()
    private let observer = DarwinConfigObserver()
    private var timer: Timer?

    func start() {
        // Apply immediately on start
        evaluateAndApply()

        // Observe config changes from the app via Darwin notification
        observer.startObserving { [weak self] in
            self?.evaluateAndApply()
        }

        // Tick every minute to handle time window changes even if no notification arrives
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.evaluateAndApply()
        }
    }

    deinit {
        timer?.invalidate()
        timer = nil
        observer.stopObserving()
    }

    private func evaluateAndApply() {
        let isAuthorized = SharedConfigStore.loadIsAuthorized()
        guard isAuthorized else {
            clearShield()
            return
        }

        let selection = SharedConfigStore.loadSelection()
        let isManual  = SharedConfigStore.loadIsManualBlockActive()
        let isSched   = SharedConfigStore.loadIsScheduleEnabled()
        let start     = SharedConfigStore.loadStartMinutes()
        let end       = SharedConfigStore.loadEndMinutes()

        let shouldBlock: Bool
        if isManual {
            shouldBlock = true
        } else if isSched {
            shouldBlock = isNowInsideWindow(startMinutes: start, endMinutes: end)
        } else {
            shouldBlock = false
        }

        if shouldBlock, (!selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty) {
            apply(selection: selection)
        } else {
            clearShield()
        }
    }

    private func apply(selection: FamilyActivitySelection) {
        // Apply apps
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens

        // Apply categories
        if selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = nil
        } else {
            store.shield.applicationCategories = .specific(selection.categoryTokens)
        }
    }

    private func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }
}

