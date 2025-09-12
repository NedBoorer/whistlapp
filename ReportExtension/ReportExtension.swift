//
//  ReportExtension.swift
//  ReportExtension
//
//  Created by Ned Boorer on 12/9/2025.
//

import DeviceActivity
import ExtensionKit
import SwiftUI

@main
struct ReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        // Home summary
        HomeReport { model in
            HomeReportView(model: model)
        }
        // Top apps
        TopAppsReport { model in
            TopThreeView(model: model)
        }
        // Total activity details
        TotalActivityReport { model in
            TotalActivityView(model: model)
        }
        // Widget-like compact summary
        WidgetReport { model in
            WidgetReportView(model: model)
        }
        // Pickups and notifications insights
        TotalPickupsReport { model in
            PickupsChartView(model: model)
        }
    }
}

