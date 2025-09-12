//
//  ReportHostView.swift
//  whistl
//
//  Created by Ned Boorer on 12/9/2025.
//

import SwiftUI
import DeviceActivityUI

// Hosts your Device Activity Report Extension inside the app.
// Starts with the "Home" context; users can navigate within the report UI.
struct ReportHostView: View {
    var body: some View {
        // The initializer with a context asks the OS to display the matching
        // DeviceActivityReportScene provided by your ReportExtension target.
        DeviceActivityReport(.home)
            .navigationTitle("Screen Time")
            .navigationBarTitleDisplayMode(.inline)
    }
}
