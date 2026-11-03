import Foundation

// MARK: - 训练课表 Schema（对齐项目文档 §3.1）

struct TrainingSessionSchema: Codable, Identifiable, Equatable {
    let id: String
    var sessionType: SessionType
    var title: String
    var totalDistanceKm: Double?
    var totalEstimatedTimeMin: Int?
    var segments: [Segment]
    var weatherNote: String?
    var wasDowngraded: Bool

    enum SessionType: String, Codable {
        case lsd = "LSD"
        case interval
        case threshold
        case easy
        case rest
        case crossTraining
    }

    init(id: String = UUID().uuidString,
         sessionType: SessionType,
         title: String,
         totalDistanceKm: Double? = nil,
         totalEstimatedTimeMin: Int? = nil,
         segments: [Segment],
         weatherNote: String? = nil,
         wasDowngraded: Bool = false) {
        self.id = id
        self.sessionType = sessionType
        self.title = title
        self.totalDistanceKm = totalDistanceKm
        self.totalEstimatedTimeMin = totalEstimatedTimeMin
        self.segments = segments
        self.weatherNote = weatherNote
        self.wasDowngraded = wasDowngraded
    }
}

struct Segment: Codable, Equatable, Identifiable {
    var id: String { segmentId }
    let segmentId: String
    var segmentType: SegmentType
    var startKm: Double?
    var endKm: Double?
    var startTimeSec: Int?
    var endTimeSec: Int?
    var paceLow: String?
    var paceHigh: String?
    var hrLow: Int?
    var hrHigh: Int?
    var note: String?

    enum SegmentType: String, Codable {
        case distance
        case time
    }

    enum CodingKeys: String, CodingKey {
        case segmentId, segmentType, startKm, endKm, startTimeSec, endTimeSec
        case paceLow, paceHigh, hrLow, hrHigh, note
    }

    init(segmentId: String = UUID().uuidString,
         segmentType: SegmentType,
         startKm: Double? = nil,
         endKm: Double? = nil,
         startTimeSec: Int? = nil,
         endTimeSec: Int? = nil,
         paceLow: String? = nil,
         paceHigh: String? = nil,
         hrLow: Int? = nil,
         hrHigh: Int? = nil,
         note: String? = nil) {
        self.segmentId = segmentId
        self.segmentType = segmentType
        self.startKm = startKm
        self.endKm = endKm
        self.startTimeSec = startTimeSec
        self.endTimeSec = endTimeSec
        self.paceLow = paceLow
        self.paceHigh = paceHigh
        self.hrLow = hrLow
        self.hrHigh = hrHigh
        self.note = note
    }
}

// MARK: - 天气快照（对齐 §3.2 weatherSnapshot）

struct WeatherSnapshot: Codable, Equatable {
    var condition: String
    var tempC: Double
    var feelsLikeC: Double
    var humidityPercent: Double
    var precipMm: Double
    var windKmh: Double
    var uvIndex: Double?
    var riskLevel: WeatherRiskLevel
    var trainingWindowStart: Date?
    var trainingWindowEnd: Date?

    enum WeatherRiskLevel: String, Codable {
        case low
        case medium
        case high
    }
}

// MARK: - 恢复快照（对齐 §3.2 recoverySnapshot）

struct RecoverySnapshot: Codable, Equatable {
    var morningHrvSdnn: Double?
    var restingHr: Double?
    var sleepTotalMin: Double?
    var sleepDeepMin: Double?
    var recoveryLevel: RecoveryLevel
    var recoveryReasons: [String] = []

    enum RecoveryLevel: String, Codable {
        case normal
        case mildFatigue
        case highFatigue
    }
}

// MARK: - 负荷快照（对齐 §3.2 loadSnapshot）

struct LoadSnapshot: Codable, Equatable {
    var last7dTrimp: Double
    var last14dTrimp: Double
    var acwrSimple: Double
}

// MARK: - 用户画像（对齐 §3.2 userProfile）

struct UserProfileSchema: Codable, Equatable {
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var gender: String
    var vo2maxEstimate: Double?
    var targetMarathonDistanceKm: Double
    var targetFinishTimeMin: Int
}

// MARK: - LLM 输入（对齐 §3.2 完整结构）

struct LLMInput: Codable {
    var userProfile: UserProfileSchema
    var recoverySnapshot: RecoverySnapshot
    var loadSnapshot: LoadSnapshot
    var weatherSnapshot: WeatherSnapshot?
    var recentSessions: [TrainingSessionSchema]
    var originalSession: TrainingSessionSchema?
    var forceOriginal: Bool
}

// MARK: - 训练日志（一次完成训练的结果）

struct WorkoutLog: Codable {
    var sessionId: String
    var startTime: Date
    var endTime: Date
    var totalDistanceMeters: Double
    var totalDurationSec: TimeInterval
    var avgHeartRate: Double
    var maxHeartRate: Double
    var trimp: Double
    var segmentResults: [SegmentResult]
}

struct SegmentResult: Codable {
    var segmentId: String
    var startedAt: Date
    var endedAt: Date
    var avgHr: Double
    var avgPaceSecPerKm: Double?
    var hrInZone: Bool
    var paceInZone: Bool
}

// MARK: - 配速解析工具

enum PaceParser {
    static func toSecondsPerKm(_ pace: String) -> Double? {
        let parts = pace.split(separator: ":")
        guard parts.count == 2,
              let min = Double(parts[0]),
              let sec = Double(parts[1]) else { return nil }
        return min * 60 + sec
    }

    static func fromSecondsPerKm(_ secPerKm: Double) -> String {
        let min = Int(secPerKm) / 60
        let sec = Int(secPerKm) % 60
        return String(format: "%d:%02d", min, sec)
    }
}
