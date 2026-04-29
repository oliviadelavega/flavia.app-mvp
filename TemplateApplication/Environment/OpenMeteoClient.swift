//
// Flavia study app
//
// Thin async wrapper around the two Open-Meteo endpoints we care about:
//   - api.open-meteo.com/v1/forecast for UV index
//   - air-quality-api.open-meteo.com/v1/air-quality for AQI + pollen
// The free tier needs no auth or API key. We hit them in parallel and fold
// the responses into an `EnvironmentSnapshot`.
//

import Foundation


actor OpenMeteoClient {
    enum ClientError: Error {
        case badResponse(status: Int)
        case decoding(Error)
        case transport(Error)
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSnapshot(
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double?,
        recordedAt: Date
    ) async throws -> EnvironmentSnapshot {
        async let uvResponse = fetchUV(latitude: latitude, longitude: longitude)
        async let airResponse = fetchAirQuality(latitude: latitude, longitude: longitude)

        let forecast = try await uvResponse
        let air = try await airResponse

        let dailyMax: Double? = {
            guard let entries = forecast.daily?.uvIndexMax else {
                return nil
            }
            return entries.first.flatMap { $0 }
        }()

        return EnvironmentSnapshot(
            location: EnvironmentLocation(
                latitude: latitude,
                longitude: longitude,
                accuracyMeters: accuracyMeters,
                timezone: forecast.timezone ?? air.timezone,
                recordedAt: recordedAt
            ),
            weather: EnvironmentWeather(
                temperatureCelsius: forecast.current?.temperature2m,
                apparentTemperatureCelsius: forecast.current?.apparentTemperature,
                relativeHumidityPercent: forecast.current?.relativeHumidity2m,
                precipitationMillimeters: forecast.current?.precipitation
            ),
            uvLevels: EnvironmentUV(
                current: forecast.current?.uvIndex,
                clearSky: forecast.current?.uvIndexClearSky,
                dailyMax: dailyMax
            ),
            airQuality: EnvironmentAirQuality(
                europeanAQI: air.current?.europeanAqi,
                usAQI: air.current?.usAqi,
                pm10: air.current?.pm10,
                pm25: air.current?.pm25,
                carbonMonoxide: air.current?.carbonMonoxide,
                nitrogenDioxide: air.current?.nitrogenDioxide,
                sulphurDioxide: air.current?.sulphurDioxide,
                ozone: air.current?.ozone
            ),
            pollen: EnvironmentPollen(
                alder: air.current?.alderPollen,
                birch: air.current?.birchPollen,
                grass: air.current?.grassPollen,
                mugwort: air.current?.mugwortPollen,
                olive: air.current?.olivePollen,
                ragweed: air.current?.ragweedPollen
            ),
            capturedAt: Date()
        )
    }

    // MARK: - UV

    private func fetchUV(latitude: Double, longitude: Double) async throws -> ForecastResponse {
        // Same call returns weather + UV; keeping it as one round-trip is cheaper than two.
        let currentFields = [
            "temperature_2m", "apparent_temperature", "relative_humidity_2m", "precipitation",
            "uv_index", "uv_index_clear_sky"
        ].joined(separator: ",")
        let url = try buildURL(
            base: "https://api.open-meteo.com/v1/forecast",
            queryItems: [
                URLQueryItem(name: "latitude", value: format(latitude)),
                URLQueryItem(name: "longitude", value: format(longitude)),
                URLQueryItem(name: "current", value: currentFields),
                URLQueryItem(name: "daily", value: "uv_index_max"),
                URLQueryItem(name: "timezone", value: "auto")
            ]
        )
        return try await get(ForecastResponse.self, from: url)
    }

    // MARK: - Air Quality + Pollen

    private func fetchAirQuality(latitude: Double, longitude: Double) async throws -> AirQualityResponse {
        let currentFields = [
            "european_aqi", "us_aqi",
            "pm10", "pm2_5",
            "carbon_monoxide", "nitrogen_dioxide", "sulphur_dioxide", "ozone",
            "alder_pollen", "birch_pollen", "grass_pollen",
            "mugwort_pollen", "olive_pollen", "ragweed_pollen"
        ].joined(separator: ",")
        let url = try buildURL(
            base: "https://air-quality-api.open-meteo.com/v1/air-quality",
            queryItems: [
                URLQueryItem(name: "latitude", value: format(latitude)),
                URLQueryItem(name: "longitude", value: format(longitude)),
                URLQueryItem(name: "current", value: currentFields),
                URLQueryItem(name: "timezone", value: "auto")
            ]
        )
        return try await get(AirQualityResponse.self, from: url)
    }

    private func buildURL(base: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(string: base) else {
            throw ClientError.transport(URLError(.badURL))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ClientError.transport(URLError(.badURL))
        }
        return url
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.badResponse(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClientError.decoding(error)
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}


// MARK: - Wire models
// Open-Meteo uses snake_case keys; we decode with `convertFromSnakeCase` so the
// Swift properties stay camelCase and pass SwiftLint's identifier_name rule.

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature2m: Double?
        let apparentTemperature: Double?
        let relativeHumidity2m: Double?
        let precipitation: Double?
        let uvIndex: Double?
        let uvIndexClearSky: Double?

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity2m = "relative_humidity_2m"
            case precipitation
            case uvIndex = "uv_index"
            case uvIndexClearSky = "uv_index_clear_sky"
        }
    }
    struct Daily: Decodable {
        let uvIndexMax: [Double?]?

        enum CodingKeys: String, CodingKey {
            case uvIndexMax = "uv_index_max"
        }
    }
    let timezone: String?
    let current: Current?
    let daily: Daily?
}


private struct AirQualityResponse: Decodable {
    struct Current: Decodable {
        let europeanAqi: Double?
        let usAqi: Double?
        let pm10: Double?
        let pm25: Double?
        let carbonMonoxide: Double?
        let nitrogenDioxide: Double?
        let sulphurDioxide: Double?
        let ozone: Double?
        let alderPollen: Double?
        let birchPollen: Double?
        let grassPollen: Double?
        let mugwortPollen: Double?
        let olivePollen: Double?
        let ragweedPollen: Double?

        enum CodingKeys: String, CodingKey {
            case europeanAqi = "european_aqi"
            case usAqi = "us_aqi"
            case pm10
            case pm25 = "pm2_5"
            case carbonMonoxide = "carbon_monoxide"
            case nitrogenDioxide = "nitrogen_dioxide"
            case sulphurDioxide = "sulphur_dioxide"
            case ozone
            case alderPollen = "alder_pollen"
            case birchPollen = "birch_pollen"
            case grassPollen = "grass_pollen"
            case mugwortPollen = "mugwort_pollen"
            case olivePollen = "olive_pollen"
            case ragweedPollen = "ragweed_pollen"
        }
    }
    let timezone: String?
    let current: Current?
}
