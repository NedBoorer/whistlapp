//
//  ShieldDataSource.swift
//  shieldwhistl
//
//  Created by Assistant on 11/9/2025.
//

import ManagedSettings
import ManagedSettingsUI
import SwiftUI

// Optional: tailor subtitle based on your shared flags (requires App Group on the extension, which you likely have)
private func subtitleText(fallback: String? = nil) -> String? {
    let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
    let manual = defaults.bool(forKey: SharedKeys.isManualBlockActive)
    let schedule = defaults.bool(forKey: SharedKeys.isScheduleEnabled)
    if manual { return "Manual block is active." }
    if schedule { return "Scheduled block is active." }
    return fallback
}

private func notifyAttemptApp() {
    // Local notification to the user
    WhistlNotifier.scheduleAttemptNotification(
        title: "Oh no — blocked by whistl",
        body: "That app is blocked right now."
    )
}

private func notifyAttemptCategory() {
    WhistlNotifier.scheduleAttemptNotification(
        title: "Oh no — blocked by whistl",
        body: "This category is blocked right now."
    )
}

private func notifyAttemptDomain(domain: String) {
    WhistlNotifier.scheduleAttemptNotification(
        title: "Oh no — blocked by whistl",
        body: "This site is blocked right now."
    )
}

final class ShieldDataSource: ShieldConfigurationDataSource {
    // Called when a shield is presented for a specific app
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        // Schedule notification on every attempt
        notifyAttemptApp()

        // If you also want to log, you can’t directly access ApplicationToken here,
        // but logging via notifications/analytics can be done in ShieldActionDelegate on button press.
        let subtitle = subtitleText(fallback: "This app is unavailable right now.")
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: .clear,
            title: .init(text: "Blocked by whistl"),
            subtitle: subtitle.map { .init(text: $0) },
            primaryButtonLabel: nil,
            secondaryButtonLabel: nil,
            icon: .init(systemName: "hand.raised.fill")
        )
    }

    // Called when a shield is presented for an app due to a category block
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        notifyAttemptCategory()
        let subtitle = subtitleText(fallback: "This category is blocked right now.")
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: .clear,
            title: .init(text: "Blocked by whistl"),
            subtitle: subtitle.map { .init(text: $0) },
            primaryButtonLabel: nil,
            secondaryButtonLabel: nil,
            icon: .init(systemName: "hand.raised.fill")
        )
    }

    // Optional: Called when a shield is presented for a blocked web domain
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        notifyAttemptDomain(domain: webDomain.domain)
        let subtitle = subtitleText(fallback: webDomain.domain)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: .clear,
            title: .init(text: "Blocked by whistl"),
            subtitle: subtitle.map { .init(text: $0) },
            primaryButtonLabel: nil,
            secondaryButtonLabel: nil,
            icon: .init(systemName: "hand.raised.fill")
        )
    }
}
