//
//  ReportHostView.swift
//  whistl
//
//  Created by Ned Boorer on 12/9/2025.
//

import SwiftUI
import DeviceActivity
import ManagedSettings

// Hosts your Device Activity Report Extension inside the app.
// This is the correct approach - you cannot directly query DeviceActivityCenter for results
// from the main app. The data must come through a DeviceActivityReport extension.
struct ReportHostView: View {
    var body: some View {
        DeviceActivityReport(.home)
            .navigationTitle("Screen Time")
            .navigationBarTitleDisplayMode(.inline)
    }
}
