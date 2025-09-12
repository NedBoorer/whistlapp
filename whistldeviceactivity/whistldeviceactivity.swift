//
//  whistldeviceactivity.swift
//  whistldeviceactivity
//
//  Created by Ned Boorer on 12/9/2025.
//

import DeviceActivity
import ExtensionKit
import SwiftUI

@main
struct whistldeviceactivity: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        // Create a report for each DeviceActivityReport.Context that your app supports.
        TotalActivityReport { totalActivity in
            TotalActivityView(totalActivity: totalActivity)
        }
        // Add more reports here...
    }
}
