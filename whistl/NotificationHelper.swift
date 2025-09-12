//
//  NotificationHelper.swift
//  whistl
//
//  Created by Ned Boorer on 11/9/2025.
//

import Foundation
import UserNotifications

public enum WhistlNotifier {
    public static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    public static func scheduleAttemptNotification(title: String = "Oh no — blocked by whistl",
                                                   body: String = "That app is blocked right now.") {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "whistl.block.attempt.\(UUID().uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
