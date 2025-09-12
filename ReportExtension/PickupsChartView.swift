//
//  PickupsChartView.swift
//  ReportExtension
//
//  Created by Ned Boorer on 12/9/2025.
//

import SwiftUI

struct PickupsChartView: View {
    let model: MoreInsightsReport

    var body: some View {
        List {
            Section("Total pickups") {
                Text("\(model.totalPickups)")
            }

            if !model.pickupsByApp.isEmpty {
                Section("Pickups by app") {
                    ForEach(model.pickupsByApp.prefix(10), id: \.0) { row in
                        HStack {
                            Text(row.0)
                            Spacer()
                            Text("\(Int(row.1))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.notificationsByApp.isEmpty {
                Section("Notifications by app") {
                    ForEach(model.notificationsByApp.prefix(10), id: \.0) { row in
                        HStack {
                            Text(row.0)
                            Spacer()
                            Text("\(Int(row.1))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    PickupsChartView(model: MoreInsightsReport(
        totalPickups: 14,
        pickupsByApp: [("Messages", 6), ("Mail", 3), ("Safari", 2)],
        notificationsByApp: [("Messages", 10), ("Mail", 4)]
    ))
}

