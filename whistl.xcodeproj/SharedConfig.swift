//
//  SharedConfig.swift
//  whistl
//
//  Shared between app and (optionally) a shield extension.
//  If you create a Managed Settings extension, add this file to BOTH targets.
//

import Foundation
import FamilyControls
import ManagedSettings

// MARK: - App Group and Notification

// If you don’t use an extension yet, this can stay as-is.
// When you add an extension, make sure this App Group exists in Signing & Capabilities.
public let appGroupID = "group.whistl"

// Darwin notification name used to nudge an extension or other process that config changed.
public let kConfigDidChangeDarwinName = "com.whistl.configDidChange"

// MARK: - Keys

public enum SharedKeys {
    public static let isAuthorized          = "fc_isAuthorized"
    public static let isScheduleEnabled     = "fc_isScheduleEnabled"
    public static let isManualBlockActive   = "fc_isManualBlockActive"
    public static let startMinutes          = "fc_startMinutes"
    public static let endMinutes            = "fc_endMinutes"
    public static let appTokensDataArray    = "fc_appTokensDataArray"
    public static let categoryTokensDataArr = "fc_categoryTokensDataArray"
}

// MARK: - Shared Storage

public struct SharedConfigStore {
    public static var defaults: UserDefaults {
        // Use the app group if available; otherwise fall back to standard (keeps you compiling even without capabilities set up).
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // Save/load the FamilyActivitySelection by storing token data representations.
    public static func save(selection: FamilyActivitySelection) {
        let appData = selection.applicationTokens.map { $0.dataRepresentation }
        let catData = selection.categoryTokens.map { $0.dataRepresentation }
        defaults.set(appData, forKey: SharedKeys.appTokensDataArray)
        defaults.set(catData, forKey: SharedKeys.categoryTokensDataArr)
    }

    public static func loadSelection() -> FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        if let appData = defaults.array(forKey: SharedKeys.appTokensDataArray) as? [Data] {
            selection.applicationTokens = Set(appData.compactMap { ApplicationToken(dataRepresentation: $0) })
        }
        if let catData = defaults.array(forKey: SharedKeys.categoryTokensDataArr) as? [Data] {
            selection.categoryTokens = Set(catData.compactMap { ActivityCategoryToken(dataRepresentation: $0) })
        }
        return selection
    }

    // Flags / schedule
    public static func save(isScheduleEnabled: Bool) {
        defaults.set(isScheduleEnabled, forKey: SharedKeys.isScheduleEnabled)
    }
    public static func save(isManualBlockActive: Bool) {
        defaults.set(isManualBlockActive, forKey: SharedKeys.isManualBlockActive)
    }
    public static func save(startMinutes: Int, endMinutes: Int) {
        defaults.set(startMinutes, forKey: SharedKeys.startMinutes)
        defaults.set(endMinutes, forKey: SharedKeys.endMinutes)
    }
    public static func save(isAuthorized: Bool) {
        defaults.set(isAuthorized, forKey: SharedKeys.isAuthorized)
    }

    public static func loadIsScheduleEnabled() -> Bool {
        defaults.bool(forKey: SharedKeys.isScheduleEnabled)
    }
    public static func loadIsManualBlockActive() -> Bool {
        defaults.bool(forKey: SharedKeys.isManualBlockActive)
    }
    public static func loadStartMinutes() -> Int {
        // Default to 9:00 PM
        defaults.object(forKey: SharedKeys.startMinutes) as? Int ?? (21 * 60)
    }
    public static func loadEndMinutes() -> Int {
        // Default to 7:00 AM
        defaults.object(forKey: SharedKeys.endMinutes) as? Int ?? (7 * 60)
    }
    public static func loadIsAuthorized() -> Bool {
        defaults.bool(forKey: SharedKeys.isAuthorized)
    }
}

// MARK: - Darwin Notification

public func postConfigDidChangeDarwinNotification() {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterPostNotification(center,
                                         CFNotificationName(kConfigDidChangeDarwinName as CFString),
                                         nil,
                                         nil,
                                         true)
}

// Optional: if you need to listen for changes in an extension or companion process
public final class DarwinConfigObserver {
    private var isObserving = false

    public init() {}

    public func startObserving(_ callback: @escaping () -> Void) {
        guard !isObserving else { return }
        isObserving = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center,
                                        Unmanaged.passUnretained(self).toOpaque(),
                                        { _, _, _, _, _ in callback() },
                                        kConfigDidChangeDarwinName as CFString,
                                        nil,
                                        .deliverImmediately)
    }

    deinit {
        stopObserving()
    }

    public func stopObserving() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
        isObserving = false
    }
}

// MARK: - Time Window Helper

// Returns true if `now` is inside the daily window [start, end), correctly handling overnight windows.
public func isNowInsideWindow(now: Date = Date(), startMinutes: Int, endMinutes: Int, calendar: Calendar = .current) -> Bool {
    let startHour = startMinutes / 60
    let startMin  = startMinutes % 60
    let endHour   = endMinutes / 60
    let endMin    = endMinutes % 60

    let startToday = calendar.date(bySettingHour: startHour, minute: startMin, second: 0, of: now) ?? now
    let endToday   = calendar.date(bySettingHour: endHour, minute: endMin, second: 0, of: now) ?? now

    if startToday == endToday { return false } // zero-length window
    if startToday < endToday {
        // Same-day window
        return now >= startToday && now < endToday
    } else {
        // Overnight window (e.g., 21:00 -> 07:00)
        return now >= startToday || now < endToday
    }
}
