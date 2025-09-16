//
//  SharedConfig.swift
//  whistl
//
//  Created by Ned Boorer on 11/9/2025.
//

import Foundation
import FamilyControls
import ManagedSettings

// MARK: - App Group and Notification

public let appGroupID = "group.whistl"
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

    // Analytics
    public static let attemptsLog           = "fc_attemptsLog_v1"          // [AttemptEvent]
    public static let blockedAccumulations  = "fc_blockedAccum_v1"         // [String: Double] keyed by yyyy-MM-dd (seconds)
    public static let currentBlockStart     = "fc_currentBlockStart_v1"    // Date when shield last turned on (if active)

    // Pause/break
    public static let pauseUntil            = "fc_pauseUntil_v1"           // Date when pause ends

    // Pair context for extensions
    public static let pairId                = "pair_id_v1"
    public static let myUID                 = "pair_my_uid_v1"
    public static let partnerUID            = "pair_partner_uid_v1"

    // Attempt logging toggle (extensions can check)
    public static let attemptLoggingEnabled = "attempt_logging_enabled_v1"

    // Cache of observed app names keyed by token hash string
    public static let appNameCache          = "app_name_cache_v1"          // [String: String]
}

// MARK: - Shared Storage

public struct SharedConfigStore {
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // Save/load the FamilyActivitySelection by encoding token sets to Data blobs.
    public static func save(selection: FamilyActivitySelection) {
        let encoder = JSONEncoder()

        let appDataArray: [Data] = selection.applicationTokens.compactMap { token in
            try? encoder.encode(token)
        }
        let catDataArray: [Data] = selection.categoryTokens.compactMap { token in
            try? encoder.encode(token)
        }

        defaults.set(appDataArray, forKey: SharedKeys.appTokensDataArray)
        defaults.set(catDataArray, forKey: SharedKeys.categoryTokensDataArr)
    }

    public static func loadSelection() -> FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        let decoder = JSONDecoder()

        if let appData = defaults.array(forKey: SharedKeys.appTokensDataArray) as? [Data] {
            let tokens: [ApplicationToken] = appData.compactMap { data in
                try? decoder.decode(ApplicationToken.self, from: data)
            }
            selection.applicationTokens = Set(tokens)
        }

        if let catData = defaults.array(forKey: SharedKeys.categoryTokensDataArr) as? [Data] {
            let tokens: [ActivityCategoryToken] = catData.compactMap { data in
                try? decoder.decode(ActivityCategoryToken.self, from: data)
            }
            selection.categoryTokens = Set(tokens)
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

    // Pause/break
    public static func savePause(until date: Date?) {
        if let date {
            defaults.set(date, forKey: SharedKeys.pauseUntil)
        } else {
            defaults.removeObject(forKey: SharedKeys.pauseUntil)
        }
    }

    public static func loadPauseUntil() -> Date? {
        defaults.object(forKey: SharedKeys.pauseUntil) as? Date
    }

    public static func isPaused(now: Date = Date()) -> Bool {
        if let until = loadPauseUntil() {
            return now < until
        }
        return false
    }

    // Pair context for extensions
    public static func savePairContext(pairId: String?, myUID: String?, partnerUID: String?) {
        if let pairId { defaults.set(pairId, forKey: SharedKeys.pairId) } else { defaults.removeObject(forKey: SharedKeys.pairId) }
        if let myUID { defaults.set(myUID, forKey: SharedKeys.myUID) } else { defaults.removeObject(forKey: SharedKeys.myUID) }
        if let partnerUID { defaults.set(partnerUID, forKey: SharedKeys.partnerUID) } else { defaults.removeObject(forKey: SharedKeys.partnerUID) }
    }

    public static func loadPairContext() -> (pairId: String?, myUID: String?, partnerUID: String?) {
        let pid = defaults.string(forKey: SharedKeys.pairId)
        let my = defaults.string(forKey: SharedKeys.myUID)
        let partner = defaults.string(forKey: SharedKeys.partnerUID)
        return (pid, my, partner)
    }

    public static func setAttemptLogging(enabled: Bool) {
        defaults.set(enabled, forKey: SharedKeys.attemptLoggingEnabled)
    }
    public static func isAttemptLoggingEnabled() -> Bool {
        defaults.bool(forKey: SharedKeys.attemptLoggingEnabled)
    }

    // App name cache
    public static func cacheAppName(hashKey: String, name: String) {
        var dict = (defaults.dictionary(forKey: SharedKeys.appNameCache) as? [String: String]) ?? [:]
        dict[hashKey] = name
        defaults.set(dict, forKey: SharedKeys.appNameCache)
    }

    public static func appName(for hashKey: String) -> String? {
        let dict = (defaults.dictionary(forKey: SharedKeys.appNameCache) as? [String: String]) ?? [:]
        return dict[hashKey]
    }
}

// MARK: - Analytics (Attempts + Blocked time)

public struct AttemptEvent: Codable, Equatable {
    public let date: Date
    public let kind: String   // "app" or "category"
    public let identifier: String // token identifier or fallback string
    
    public init(date: Date, kind: String, identifier: String) {
        self.date = date
        self.kind = kind
        self.identifier = identifier
    }
}

public enum AnalyticsStore {
    // Append an attempt event
    public static func logAttempt(for application: ApplicationToken) {
        let identifier = "app_\(application.hashValue)"
        appendAttempt(kind: "app", identifier: identifier)
    }

    public static func logAttempt(for category: ActivityCategoryToken) {
        let identifier = "category_\(category.hashValue)"
        appendAttempt(kind: "category", identifier: identifier)
    }

    private static func appendAttempt(kind: String, identifier: String) {
        let event = AttemptEvent(date: Date(), kind: kind, identifier: identifier)
        var events = loadAttempts()
        events.append(event)
        saveAttempts(events)
    }

    private static func saveAttempts(_ events: [AttemptEvent]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(events) {
            SharedConfigStore.defaults.set(data, forKey: SharedKeys.attemptsLog)
        }
    }

    public static func loadAttempts() -> [AttemptEvent] {
        guard let data = SharedConfigStore.defaults.data(forKey: SharedKeys.attemptsLog) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([AttemptEvent].self, from: data)) ?? []
    }

    // Return attempts that occurred "today" in the current calendar
    public static func attemptsToday(calendar: Calendar = .current) -> [AttemptEvent] {
        let events = loadAttempts()
        let startOfDay = calendar.startOfDay(for: Date())
        return events.filter { $0.date >= startOfDay }
    }

    // Top culprits by attempts today
    public static func topCulpritsToday(limit: Int = 5, calendar: Calendar = .current) -> [(identifier: String, count: Int, kind: String)] {
        let todays = attemptsToday(calendar: calendar)
        var counts: [String: (count: Int, kind: String)] = [:]
        for e in todays {
            let key = "\(e.kind):\(e.identifier)"
            let current = counts[key]?.count ?? 0
            counts[key] = (current + 1, e.kind)
        }
        let sorted = counts.sorted { $0.value.count > $1.value.count }
        return Array(sorted.prefix(limit)).map { entry in
            let comps = entry.key.split(separator: ":", maxSplits: 1).map(String.init)
            let kind = comps.first ?? "app"
            let id = comps.count > 1 ? comps[1] : entry.key
            return (identifier: id, count: entry.value.count, kind: kind)
        }
    }

    // Blocked time accumulation (seconds) keyed by yyyy-MM-dd
    public static func markShieldActivated(now: Date = Date(), calendar: Calendar = .current) {
        if SharedConfigStore.defaults.object(forKey: SharedKeys.currentBlockStart) as? Date != nil { return }
        SharedConfigStore.defaults.set(now, forKey: SharedKeys.currentBlockStart)
    }

    public static func markShieldDeactivated(now: Date = Date(), calendar: Calendar = .current) {
        guard let start = SharedConfigStore.defaults.object(forKey: SharedKeys.currentBlockStart) as? Date else { return }
        SharedConfigStore.defaults.removeObject(forKey: SharedKeys.currentBlockStart)
        let seconds = max(0, now.timeIntervalSince(start))
        accumulate(seconds: seconds, at: start, calendar: calendar)
    }

    public static func finalizeIfDayRolledOver(now: Date = Date(), calendar: Calendar = .current) {
        guard let start = SharedConfigStore.defaults.object(forKey: SharedKeys.currentBlockStart) as? Date else { return }
        let startDay = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)
        guard today > startDay else { return }
        if let endOfStartDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startDay) {
            let seconds = max(0, endOfStartDay.timeIntervalSince(start))
            accumulate(seconds: seconds, at: start, calendar: calendar)
            SharedConfigStore.defaults.set(today, forKey: SharedKeys.currentBlockStart)
        }
    }

    public static func blockedSecondsToday(now: Date = Date(), calendar: Calendar = .current) -> Int {
        finalizeIfDayRolledOver(now: now, calendar: calendar)
        let key = dayKey(for: now, calendar: calendar)
        let dict = (SharedConfigStore.defaults.dictionary(forKey: SharedKeys.blockedAccumulations) as? [String: Double]) ?? [:]
        var total = Int(dict[key] ?? 0)
        if let currentStart = SharedConfigStore.defaults.object(forKey: SharedKeys.currentBlockStart) as? Date {
            let startOfToday = calendar.startOfDay(for: now)
            let effectiveStart = max(currentStart, startOfToday)
            total += Int(max(0, now.timeIntervalSince(effectiveStart)))
        }
        return total
    }

    private static func accumulate(seconds: TimeInterval, at date: Date, calendar: Calendar) {
        let key = dayKey(for: date, calendar: calendar)
        var dict = (SharedConfigStore.defaults.dictionary(forKey: SharedKeys.blockedAccumulations) as? [String: Double]) ?? [:]
        dict[key] = (dict[key] ?? 0) + seconds
        SharedConfigStore.defaults.set(dict, forKey: SharedKeys.blockedAccumulations)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
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


// MARK: - Time Window Helper

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

