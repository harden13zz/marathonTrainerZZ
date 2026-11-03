import SwiftUI

struct TodayView: View {
    @StateObject private var weather = WeatherService()
    @StateObject private var engine = WorkoutEngine()
    @Environment(\.modelContext) private var context

    @State private var todaySession: TrainingSessionSchema?
    @State private var showWorkout = false

    var body: some View {
        NavigationStack {
            Group {
                if engine.state == .running || engine.state == .paused {
                    WorkoutActiveView(engine: engine)
                } else {
                    todayContent
                }
            }
            .navigationTitle("今日训练")
        }
        .onAppear { loadToday() }
        .fullScreenCover(isPresented: $showWorkout) {
            if let s = todaySession {
                WorkoutActiveView(engine: engine)
                    .onAppear { engine.start(session: s) }
            }
        }
    }

    private var todayContent: some View {
        List {
            if let snapshot = weather.currentSnapshot {
                Section("天气") {
                    WeatherCardView(snapshot: snapshot)
                }
            }

            Section("今日课表") {
                if let session = todaySession {
                    Text(session.title).font(.headline)
                    Text("\(session.segments.count) 段 · \(session.sessionType.rawValue)")
                        .foregroundStyle(.secondary)

                    ForEach(Array(session.segments.enumerated()), id: \.element.id) { idx, seg in
                        SegmentRowView(index: idx + 1, segment: seg)
                    }

                    if session.wasDowngraded {
                        Label("已因恢复/天气自动降级", systemImage: "arrow.down.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }

                    Button {
                        showWorkout = true
                    } label: {
                        Label("开始训练", systemImage: "figure.run")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    Text("今日暂无课表")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadToday() {
        let descriptor = FetchDescriptor<TrainingSessionRecord>(
            predicate: #Predicate { $date >= Calendar.current.startOfDay(for: Date()) }
        )
        if let record = try? context.fetch(descriptor).first,
           let data = record.segmentsJson.data(using: .utf8),
           let segments = try? JSONDecoder().decode([Segment].self, from: data) {
            todaySession = TrainingSessionSchema(
                id: record.id, sessionType: .easy, title: record.title,
                totalDistanceKm: record.totalDistanceKm,
                totalEstimatedTimeMin: record.totalEstimatedTimeMin,
                segments: segments, wasDowngraded: record.wasDowngraded
            )
        }

        Task {
            await weather.fetchWeather(latitude: 34.34, longitude: 108.94)
        }
    }
}

// MARK: - 训练进行中视图

struct WorkoutActiveView: View {
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("第 \(engine.currentSegmentIndex + 1)/\(engine.totalSegments) 段")
                        .font(.caption).foregroundStyle(.secondary)
                    if let seg = engine.currentSegment {
                        Text(seg.note ?? "").font(.headline)
                    }
                }
                Spacer()
                Text(engine.elapsedText).font(.system(size: 36, design: .monospaced))
            }
            .padding(.horizontal)

            HStack(spacing: 30) {
                MetricView(label: "心率", value: engine.currentHR > 0 ? "\(Int(engine.currentHR))" : "--", unit: "bpm")
                MetricView(label: "距离", value: String(format: "%.2f", engine.distanceMeters / 1000), unit: "km")
            }

            if let alert = engine.alertMessage {
                Text(alert)
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                    .padding(.vertical, 4)
            }

            Spacer()

            HStack(spacing: 20) {
                if engine.state == .running {
                    Button { engine.pause() } label: {
                        Image(systemName: "pause.circle.fill").font(.system(size: 50))
                    }.tint(.yellow)
                } else if engine.state == .paused {
                    Button { engine.resume() } label: {
                        Image(systemName: "play.circle.fill").font(.system(size: 50))
                    }.tint(.green)
                }
                Button { engine.stop() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 50))
                }.tint(.red)
            }
        }
        .padding()
    }
}

// MARK: - 辅助视图

struct MetricView: View {
    var label: String
    var value: String
    var unit: String
    var body: some View {
        VStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct WeatherCardView: View {
    var snapshot: WeatherSnapshot
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(snapshot.tempC))°C  \(snapshot.condition)")
                Text("体感 \(Int(snapshot.feelsLikeC))°C · 湿度 \(Int(snapshot.humidityPercent))% · 风 \(Int(snapshot.windKmh))km/h")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            riskBadge
        }
    }
    private var riskBadge: some View {
        let color: Color = snapshot.riskLevel == .high ? .red : snapshot.riskLevel == .medium ? .orange : .green
        let text = snapshot.riskLevel == .high ? "高风险" : snapshot.riskLevel == .medium ? "注意" : "适宜"
        return Text(text).font(.caption.bold()).padding(6).background(color.opacity(0.2), in: Capsule()).foregroundStyle(color)
    }
}

struct SegmentRowView: View {
    var index: Int
    var segment: Segment
    var body: some View {
        HStack {
            Text("\(index)").font(.caption.monospaced()).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.note ?? segmentTypeText).font(.subheadline)
                HStack(spacing: 8) {
                    if let low = segment.hrLow, let high = segment.hrHigh {
                        Text("HR \(low)-\(high)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let pl = segment.paceLow, let ph = segment.paceHigh {
                        Text("配速 \(pl)-\(ph)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private var segmentTypeText: String {
        switch segment.segmentType {
        case .distance:
            if let s = segment.startKm, let e = segment.endKm { return "\(s)-\(e)km" }
        case .time:
            if let s = segment.startTimeSec, let e = segment.endTimeSec { return "\(s/60)-\(e/60)min" }
        }
        return "段"
    }
}
