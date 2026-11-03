import SwiftUI
import SwiftData

struct TodayView: View {
    @StateObject private var weather = WeatherService()
    @StateObject private var engine = WorkoutEngine()
    @Environment(\.modelContext) private var context

    @State private var todaySession: TrainingSessionSchema?
    @State private var showWorkout = false
    @State private var recovery: RecoverySnapshot?
    @State private var isGeneratingPlan = false

    var body: some View {
        NavigationStack {
            Group {
                if engine.state == .running || engine.state == .paused {
                    WorkoutActiveView(engine: engine)
                } else if engine.state == .finished {
                    WorkoutSummaryView(engine: engine) {
                        engine.reset()
                    }
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

            if let recovery = recovery {
                Section("恢复状态") {
                    RecoveryBadgeView(recovery: recovery)
                }
            }

            Section("今日训练") {
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
                    Text("今日暂无训练计划")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await generatePlan() }
                } label: {
                    Label(isGeneratingPlan ? "生成中..." : "生成本周计划", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isGeneratingPlan)
            }
        }
    }

    private func loadToday() {
        let dayStart = Calendar.current.startOfDay(for: Date())
        let all = (try? context.fetch(FetchDescriptor<TrainingSessionRecord>())) ?? []
        if let record = all.filter({ $0.date >= dayStart }).min(by: { $0.date < $1.date }),
           let data = record.segmentsJson.data(using: .utf8),
           let segments = try? JSONDecoder().decode([Segment].self, from: data) {
            todaySession = TrainingSessionSchema(
                id: record.id,
                sessionType: TrainingSessionSchema.SessionType(rawValue: record.sessionType) ?? .easy,
                title: record.title,
                totalDistanceKm: record.totalDistanceKm,
                totalEstimatedTimeMin: record.totalEstimatedTimeMin,
                segments: segments,
                weatherNote: record.weatherNote,
                wasDowngraded: record.wasDowngraded
            )
        }

        Task {
            let city = SecureStore.shared.fixedCity.trimmingCharacters(in: .whitespaces)
            if city.isEmpty {
                await weather.fetchWeather(latitude: 34.34, longitude: 108.94)
            } else {
                await weather.fetchWeather(city: city)
            }

            let assessor = RecoveryAssessor()
            let inputs = await assessor.fetchTodayRecovery()
            recovery = assessor.assess(inputs: inputs)
        }
    }

    private func generatePlan() async {
        isGeneratingPlan = true
        defer { isGeneratingPlan = false }

        let profile = SecureStore.shared.userProfile
        let assessor = RecoveryAssessor()
        let inputs = await assessor.fetchTodayRecovery()
        let recoverySnapshot = assessor.assess(inputs: inputs)

        let input = PlanGenerator.PlanInput(
            profile: profile,
            recovery: recoverySnapshot,
            weather: weather.currentSnapshot,
            recentSessions: [],
            weekNumber: 1
        )

        do {
            let generator = PlanGenerator()
            _ = try await generator.generateWeeklyPlan(input: input, context: context)
            loadToday()
        } catch {
            print("计划生成失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 训练总结视图

struct WorkoutSummaryView: View {
    @ObservedObject var engine: WorkoutEngine
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("训练完成！")
                .font(.title2.bold())

            VStack(spacing: 12) {
                MetricView(label: "总时间", value: engine.elapsedText, unit: "")
                MetricView(label: "总距离", value: String(format: "%.2f", engine.distanceMeters / 1000), unit: "km")
                MetricView(label: "平均心率", value: engine.currentHR > 0 ? "\(Int(engine.currentHR))" : "--", unit: "bpm")
            }
            .padding()

            Button {
                onDone()
            } label: {
                Label("返回", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding()
    }
}

// MARK: - 恢复状态徽章

struct RecoveryBadgeView: View {
    let recovery: RecoverySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recoveryLevelText).font(.headline)
                Spacer()
                Circle()
                    .fill(recoveryLevelColor)
                    .frame(width: 12, height: 12)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let hrv = recovery.morningHrvSdnn {
                    Label("HRV: \(Int(hrv)) ms", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let sleep = recovery.sleepTotalMin {
                    Label("睡眠：\(Int(sleep/60))h \(Int(sleep.truncatingRemainder(dividingBy: 60)))m", systemImage: "bed.double.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let restingHR = recovery.restingHr {
                    Label("静息心率：\(Int(restingHR)) bpm", systemImage: "heart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(recoveryExplanation)
                .font(.caption)
                .foregroundStyle(recoveryLevelColor)
                .padding(.top, 4)
        }
    }

    private var recoveryLevelText: String {
        switch recovery.recoveryLevel {
        case .normal: return "状态良好"
        case .mildFatigue: return "轻度疲劳"
        case .highFatigue: return "高度疲劳"
        }
    }

    private var recoveryLevelColor: Color {
        switch recovery.recoveryLevel {
        case .normal: return .green
        case .mildFatigue: return .yellow
        case .highFatigue: return .red
        }
    }

    private var recoveryExplanation: String {
        switch recovery.recoveryLevel {
        case .normal:
            return "各项指标正常，可以正常训练"
        case .mildFatigue:
            var reasons: [String] = []
            if let hrv = recovery.morningHrvSdnn, hrv < 50 {
                reasons.append("HRV 偏低")
            }
            if let sleep = recovery.sleepTotalMin, sleep < 7 * 60 {
                reasons.append("睡眠不足")
            }
            if let hr = recovery.restingHr, hr > 75 {
                reasons.append("静息心率偏高")
            }
            return "建议降低强度：\(reasons.joined(separator: "、"))"
        case .highFatigue:
            var reasons: [String] = []
            if let hrv = recovery.morningHrvSdnn, hrv < 40 {
                reasons.append("HRV 过低")
            }
            if let sleep = recovery.sleepTotalMin, sleep < 6 * 60 {
                reasons.append("严重睡眠不足")
            }
            if let hr = recovery.restingHr, hr > 85 {
                reasons.append("静息心率过高")
            }
            return "建议休息：\(reasons.joined(separator: "、"))"
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
