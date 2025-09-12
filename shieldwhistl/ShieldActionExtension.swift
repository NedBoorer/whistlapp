//
//  ShieldActionExtension.swift
//  shieldwhistl
//
//  Created by Ned Boorer on 11/9/2025.
//

import ManagedSettings

class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        // Log attempt
        AnalyticsStore.logAttempt(for: application)

        switch action {
        case .primaryButtonPressed:
            // Gentle mateship reinforcement.
            WhistlNotifier.scheduleAttemptNotification(
                title: "Nice one — you stayed on track",
                body: "Your mate’s with you. You’ve got this."
            )
            completionHandler(.close)
        case .secondaryButtonPressed:
            completionHandler(.defer)
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        // Log attempt
        AnalyticsStore.logAttempt(for: category)

        // Same reinforcement if a button is present for category shields.
        WhistlNotifier.scheduleAttemptNotification(
            title: "Nice one — you stayed on track",
            body: "Your mate’s with you. You’ve got this."
        )
        completionHandler(.close)
    }
}

