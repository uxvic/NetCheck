import SwiftUI
import Charts

/// Tiny dual-line history of down/up rates, fed from `NetworkMonitor.history`.
struct SparklineView: View {
    let samples: [NetworkMonitor.RateSample]

    var body: some View {
        Chart {
            ForEach(samples) { s in
                LineMark(x: .value("t", s.id), y: .value("rate", s.down), series: .value("dir", "Down"))
                    .foregroundStyle(by: .value("dir", "Down"))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", s.id), y: .value("rate", s.up), series: .value("dir", "Up"))
                    .foregroundStyle(by: .value("dir", "Up"))
                    .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale(["Down": Color.blue, "Up": Color.green])
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .overlay(alignment: .center) {
            if samples.count < 2 {
                Text("Collecting…").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
