//
//  WidgetReport.swift
//  com.whistl.whistl.reportextension
//

import DeviceActivity
import SwiftUI

struct WidgetReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .widget

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> some DeviceActivityReport.Configuration {
        var total: TimeInterval = 0

        for await result in data {
            for await segment in result.activitySegments {
                total += segment.totalActivityDuration
            }
        }

        let report = TotalActivityWidgetReport(totalMinutes: total / 60.0)
        return WidgetReportView(report: report)
    }
}

