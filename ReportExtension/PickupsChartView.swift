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
                    ForEach(model.pickupsByApp.prefix(10), id: \.name) { row in
                        HStack {
                            Text(row.name)
                            Spacer()
                            Text("\(Int(row.value))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.notificationsByApp.isEmpty {
                Section("Notifications by app") {
                    ForEach(model.notificationsByApp.prefix(10), id: \.name) { row in
                        HStack {
                            Text(row.name)
                            Spacer()
                            Text("\(Int(row.value))")
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
        pickupsByApp: [NamedCount(name: "Messages", value: 6), NamedCount(name: "Mail", value: 3), NamedCount(name: "Safari", value: 2)],
        notificationsByApp: [NamedCount(name: "Messages", value: 10), NamedCount(name: "Mail", value: 4)]
    ))
}
