//
//  SharedConfig.swift
//  whistl
//
//  Shared between app and shield extension.
//  Make sure this file is added to BOTH targets: the app and the shield extension.
//

import Foundation
import FamilyControls
import ManagedSettings

// MARK: - App Group and Notification

public let appGroupID = "group.whistl"

// Darwin notification to wake the extension when the app updates config
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
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // Selection encode/decode
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
        defaults.object(forKey: SharedKeys.startMinutes) as? Int ?? (21 * 60)
    }
    public static func loadEndMinutes() -> Int {
        defaults.object(forKey: SharedKeys.endMinutes) as? Int ?? (7 * 60)
    }
    public static func loadIsAuthorized() -> Bool {
        defaults.bool(forKey: SharedKeys.isAuthorized)
    }
}

// MARK: - Notification

public func postConfigDidChangeDarwinNotification() {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterPostNotification(center, CFNotificationName(kConfigDidChangeDarwinName as CFString), nil, nil, true)
}

public final class DarwinConfigObserver {
    private var token: CFNotificationCenter?
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
        token = center
    }

    deinit {
        stopObserving()
    }

    public func stopObserving() {
        guard isObserving, let center = token else { return }
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
        isObserving = false
    }
}

// MARK: - Time Window

public func isNowInsideWindow(now: Date = Date(), startMinutes: Int, endMinutes: Int, calendar: Calendar = .current) -> Bool {
    let startHour = startMinutes / 60
    let startMin  = startMinutes % 60
    let endHour   = endMinutes / 60
    let endMin    = endMinutes % 60

    let startToday = calendar.date(bySettingHour: startHour, minute: startMin, second: 0, of: now) ?? now
    let endToday   = calendar.date(bySettingHour: endHour, minute: endMin, second: 0, of: now) ?? now

    if startToday == endToday { return false }
    if startToday < endToday {
        return now >= startToday && now < endToday
    } else {
        return now >= startToday || now < endToday
    }
}

