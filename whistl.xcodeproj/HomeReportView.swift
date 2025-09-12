//
//  HomeReportView.swift
//  com.whistl.whistl.reportextension
//

import SwiftUI
import DeviceActivity

struct HomeReportView: DeviceActivityReportView {
    let report: ChartAndTopThreeReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top apps")
                .font(.headline)
            ForEach(report.topApps.prefix(3), id: \.id) { app in
                HStack {
                    Text(app.name)
                    Spacer()
                    Text(formatMinutes(app.duration))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("Categories")
                .font(.headline)
            MiniBars(pairs: report.categoryChart)

            Text("Apps")
                .font(.headline)
            MiniBars(pairs: report.appChart)
        }
        .padding()
    }

    private func formatMinutes(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        return "\(m)m"
    }
}

struct MiniBars: View {
    let pairs: [(String, Double)]
    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(pairs.prefix(5)).indices, id: \.self) { i in
                let item = pairs[i]
                HStack {
                    Text(item.0).lineLimit(1)
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 4).fill(Color.accentColor)
                                .frame(width: max(2, geo.size.width * widthFraction(i)))
                        }
                    }
                    .frame(width: 120, height: 8)
                    Text("\(Int(item.1))m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    private func widthFraction(_ idx: Int) -> CGFloat {
        guard let maxValue = pairs.map({ $0.1 }).max(), maxValue > 0 else { return 0.0 }
        let v = pairs[idx].1
        return CGFloat(v / maxValue)
    }
}

