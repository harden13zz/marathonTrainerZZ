import Foundation

@MainActor
final class WeatherService: ObservableObject {

    @Published var currentSnapshot: WeatherSnapshot?
    @Published var isLoading = false
    @Published var error: String?

    private let cacheKey = "mt_weather_cache"
    private let cacheTimeKey = "mt_weather_cache_time"
    private let cacheDuration: TimeInterval = 4 * 3600

    struct CachedWeather: Codable {
        var snapshot: WeatherSnapshot
        var latitude: Double
        var longitude: Double
    }

    func fetchWeather(latitude: Double, longitude: Double,
                      trainingStart: Date? = nil, trainingEnd: Date? = nil) async {
        if let cached = loadCache(lat: latitude, lon: longitude),
           Date().timeIntervalSince1970 - cached.age < cacheDuration {
            currentSnapshot = cached.snapshot
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let snapshot = try await requestOpenMeteo(lat: latitude, lon: longitude,
                                                       trainingStart: trainingStart,
                                                       trainingEnd: trainingEnd)
            currentSnapshot = snapshot
            saveCache(snapshot, lat: latitude, lon: longitude)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func fetchWeather(city: String, trainingStart: Date? = nil, trainingEnd: Date? = nil) async {
        guard let coord = geocode(city: city) else {
            error = "无法解析城市: \(city)"
            return
        }
        await fetchWeather(latitude: coord.lat, longitude: coord.lon,
                          trainingStart: trainingStart, trainingEnd: trainingEnd)
    }

    // MARK: - Open-Meteo API

    private func requestOpenMeteo(lat: Double, lon: Double,
                                   trainingStart: Date?, trainingEnd: Date?) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
            URLQueryItem(name: "hourly", value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,wind_speed_10m,uv_index,weather_code"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Weather", code: 1, userInfo: [NSLocalizedDescriptionKey: "天气请求失败"])
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(OpenMeteoResponse.self, from: data)
        return buildSnapshot(from: decoded, trainingStart: trainingStart, trainingEnd: trainingEnd)
    }

    private func buildSnapshot(from resp: OpenMeteoResponse,
                                trainingStart: Date?, trainingEnd: Date?) -> WeatherSnapshot {
        let hourly = resp.hourly
        let targetHour: Int

        if let start = trainingStart {
            targetHour = Calendar.current.component(.hour, from: start)
        } else {
            targetHour = Calendar.current.component(.hour, from: Date())
        }

        let hourlyCount = hourly.temperature2m?.count ?? 0
        guard hourlyCount > 0 else {
            return WeatherSnapshot(
                condition: "unknown", tempC: 20, feelsLikeC: 20, humidityPercent: 50,
                precipMm: 0, windKmh: 0, uvIndex: nil, riskLevel: .low,
                trainingWindowStart: trainingStart, trainingWindowEnd: trainingEnd
            )
        }
        let idx = min(targetHour, hourlyCount - 1)

        let temp = hourly.temperature2m?[idx] ?? 20
        let feels = hourly.apparentTemperature?[idx] ?? temp
        let humidity = hourly.relativeHumidity2m?[idx] ?? 50
        let precip = hourly.precipitation?[idx] ?? 0
        let wind = hourly.windSpeed10m?[idx] ?? 0
        let uv = hourly.uvIndex?[idx]
        let code = hourly.weatherCode?[idx] ?? 0

        let risk = WeatherRisk.assess(tempC: temp, feelsLikeC: feels,
                                       humidity: humidity, precipMm: precip,
                                       windKmh: wind, uvIndex: uv)

        return WeatherSnapshot(
            condition: weatherCodeDescription(code),
            tempC: temp,
            feelsLikeC: feels,
            humidityPercent: humidity,
            precipMm: precip,
            windKmh: wind,
            uvIndex: uv,
            riskLevel: risk,
            trainingWindowStart: trainingStart,
            trainingWindowEnd: trainingEnd
        )
    }

    private func weatherCodeDescription(_ code: Int) -> String {
        switch code {
        case 0: return "sunny"
        case 1...3: return "cloudy"
        case 45, 48: return "foggy"
        case 51...67: return "rainy"
        case 71...77: return "snowy"
        case 80...82: return "rainy"
        case 95...99: return "extreme"
        default: return "cloudy"
        }
    }

    // MARK: - 简易地理编码（西安为主）

    private func geocode(city: String) -> (lat: Double, lon: Double)? {
        let known: [String: (Double, Double)] = [
            "西安": (34.34, 108.94),
            "xian": (34.34, 108.94),
            "北京": (39.90, 116.40),
            "上海": (31.23, 121.47),
            "广州": (23.13, 113.26),
            "成都": (30.57, 104.07),
            "武汉": (30.59, 114.30),
        ]
        let lower = city.lowercased().trimmingCharacters(in: .whitespaces)
        return known[lower] ?? known[city]
    }

    // MARK: - 缓存

    private struct CacheEntry {
        var snapshot: WeatherSnapshot
        var age: TimeInterval
    }

    private func loadCache(lat: Double, lon: Double) -> CacheEntry? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let time = UserDefaults.standard.object(forKey: cacheTimeKey) as? TimeInterval,
              let cached = try? JSONDecoder().decode(CachedWeather.self, from: data),
              abs(cached.latitude - lat) < 0.01,
              abs(cached.longitude - lon) < 0.01
        else { return nil }
        return CacheEntry(snapshot: cached.snapshot,
                         age: Date().timeIntervalSince1970 - time)
    }

    private func saveCache(_ snapshot: WeatherSnapshot, lat: Double, lon: Double) {
        let entry = CachedWeather(snapshot: snapshot, latitude: lat, longitude: lon)
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimeKey)
        }
    }
}

// MARK: - Open-Meteo 响应模型

struct OpenMeteoResponse: Codable {
    struct Hourly: Codable {
        var time: [String]?
        var temperature2m: [Double]?
        var apparentTemperature: [Double]?
        var relativeHumidity2m: [Double]?
        var precipitation: [Double]?
        var windSpeed10m: [Double]?
        var uvIndex: [Double]?
        var weatherCode: [Int]?
    }
    var hourly: Hourly
}

enum WeatherRisk {
    static func assess(tempC: Double, feelsLikeC: Double, humidity: Double,
                       precipMm: Double, windKmh: Double, uvIndex: Double?) -> WeatherSnapshot.WeatherRiskLevel {
        var score = 0

        if feelsLikeC >= 35 { score += 3 }
        else if feelsLikeC >= 30 { score += 1 }

        if humidity >= 80 && tempC >= 28 { score += 2 }
        else if humidity >= 70 { score += 1 }

        if precipMm >= 10 { score += 3 }
        else if precipMm >= 2 { score += 1 }

        if windKmh >= 50 { score += 3 }
        else if windKmh >= 30 { score += 1 }

        if let uv = uvIndex, uv >= 9 { score += 1 }

        switch score {
        case 0...2: return .low
        case 3...5: return .medium
        default: return .high
        }
    }
}
