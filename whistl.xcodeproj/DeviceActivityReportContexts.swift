//
//  DeviceActivityReportContexts.swift
//  com.whistl.whistl.reportextension
//

import DeviceActivity

// Bridge ReportingContext (shared enum in the app) to the extension's DeviceActivityReport.Context.
extension DeviceActivityReport.Context {
    static let home = DeviceActivityReport.Context(ReportingContext.home.rawValue)
    static let totalActivity = DeviceActivityReport.Context(ReportingContext.totalActivity.rawValue)
    static let topApps = DeviceActivityReport.Context(ReportingContext.topApps.rawValue)
    static let totalPickups = DeviceActivityReport.Context(ReportingContext.totalPickups.rawValue)
    static let moreInsights = DeviceActivityReport.Context(ReportingContext.moreInsights.rawValue)
    static let widget = DeviceActivityReport.Context(ReportingContext.widget.rawValue)
}

