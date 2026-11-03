import Foundation
import SwiftData

// MARK: - @Model 实体（对齐项目文档 §3.3）

@Model
final class UserProfileRecord {
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var gender: String
    var vo2maxEstimate: Double?
    var targetMarathonDistanceKm: Double
    var targetFinishTimeMin: Int
    var fixedCity: String?
    var createdAt: Date

    init(age: Int, heightCm: Double, weightKg: Double, gender: String,
         vo2maxEstimate: Double? = nil,
         targetMarathonDistanceKm: Double = 42.195,
         targetFinishTimeMin: Int = 270,
         fixedCity: String? = nil) {
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.gender = gender
        self.vo2maxEstimate = vo2maxEstimate
        self.targetMarathonDistanceKm = targetMarathonDistanceKm
        self.targetFinishTimeMin = targetFinishTimeMin
        self.fixedCity = fixedCity
        self.createdAt = Date()
    }
}

@Model
final class DailyRecoveryRecord {
    var date: Date
    var morningHrvSdnn: Double?
    var restingHr: Double?
    var sleepTotalMin: Double?
    var sleepDeepMin: Double?
    var recoveryLevel: String

    init(date: Date, morningHrvSdnn: Double?, restingHr: Double?,
         sleepTotalMin: Double?, sleepDeepMin: Double?, recoveryLevel: String) {
        self.date = date
        self.morningHrvSdnn = morningHrvSdnn
        self.restingHr = restingHr
        self.sleepTotalMin = sleepTotalMin
        self.sleepDeepMin = sleepDeepMin
        self.recoveryLevel = recoveryLevel
    }
}

@Model
final class DailyWeatherRecord {
    var date: Date
    var tempC: Double
    var feelsLikeC: Double
    var humidityPercent: Double
    var precipMm: Double
    var windKmh: Double
    var uvIndex: Double?
    var condition: String
    var riskLevel: String

    init(date: Date, tempC: Double, feelsLikeC: Double, humidityPercent: Double,
         precipMm: Double, windKmh: Double, uvIndex: Double?,
         condition: String, riskLevel: String) {
        self.date = date
        self.tempC = tempC
        self.feelsLikeC = feelsLikeC
        self.humidityPercent = humidityPercent
        self.precipMm = precipMm
        self.windKmh = windKmh
        self.uvIndex = uvIndex
        self.condition = condition
        self.riskLevel = riskLevel
    }
}

@Model
final class TrainingPlanRecord {
    var id: String
    var createdAt: Date
    var weekNumber: Int
    var sessionsJson: String
    var isActive: Bool

    init(id: String = UUID().uuidString, weekNumber: Int, sessionsJson: String, isActive: Bool = true) {
        self.id = id
        self.createdAt = Date()
        self.weekNumber = weekNumber
        self.sessionsJson = sessionsJson
        self.isActive = isActive
    }
}

@Model
final class TrainingSessionRecord {
    var id: String
    var date: Date
    var sessionType: String
    var title: String
    var segmentsJson: String
    var totalDistanceKm: Double?
    var totalEstimatedTimeMin: Int?
    var wasDowngraded: Bool
    var weatherNote: String?
    var completed: Bool

    init(id: String, date: Date, sessionType: String, title: String,
         segmentsJson: String, totalDistanceKm: Double?, totalEstimatedTimeMin: Int?,
         wasDowngraded: Bool = false, weatherNote: String? = nil) {
        self.id = id
        self.date = date
        self.sessionType = sessionType
        self.title = title
        self.segmentsJson = segmentsJson
        self.totalDistanceKm = totalDistanceKm
        self.totalEstimatedTimeMin = totalEstimatedTimeMin
        self.wasDowngraded = wasDowngraded
        self.weatherNote = weatherNote
        self.completed = false
    }
}

@Model
final class TrainingLogRecord {
    var sessionId: String
    var startTime: Date
    var endTime: Date
    var totalDistanceMeters: Double
    var totalDurationSec: Double
    var avgHeartRate: Double
    var maxHeartRate: Double
    var trimp: Double
    var logJson: String

    init(sessionId: String, startTime: Date, endTime: Date,
         totalDistanceMeters: Double, totalDurationSec: Double,
         avgHeartRate: Double, maxHeartRate: Double, trimp: Double, logJson: String) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.endTime = endTime
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDurationSec = totalDurationSec
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.trimp = trimp
        self.logJson = logJson
    }
}

@Model
final class AppNoteRecord {
    var id: String
    var sessionId: String?
    var text: String
    var createdAt: Date

    init(id: String = UUID().uuidString, sessionId: String? = nil, text: String) {
        self.id = id
        self.sessionId = sessionId
        self.text = text
        self.createdAt = Date()
    }
}

// MARK: - ModelContainer 工厂

enum StoreFactory {
    static let shared: ModelContainer = {
        let schema = Schema([
            UserProfileRecord.self,
            DailyRecoveryRecord.self,
            DailyWeatherRecord.self,
            TrainingPlanRecord.self,
            TrainingSessionRecord.self,
            TrainingLogRecord.self,
            AppNoteRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
