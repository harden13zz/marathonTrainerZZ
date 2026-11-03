import SwiftUI

struct HistoryView: View {
    @Query(sort: \TrainingLogRecord.startTime, order: .reverse) private var logs: [TrainingLogRecord]

    var body: some View {
        NavigationStack {
            List {
                if logs.isEmpty {
                    Text("暂无训练记录").foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.startTime, style: .date).font(.headline)
                            HStack(spacing: 16) {
                                Label(String(format: "%.1f km", log.totalDistanceMeters / 1000), systemImage: "figure.run")
                                Label("\(Int(log.totalDurationSec / 60)) min", systemImage: "clock")
                                Label("\(Int(log.avgHeartRate)) bpm", systemImage: "heart")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("历史")
        }
    }
}
