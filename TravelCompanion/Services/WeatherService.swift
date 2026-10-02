import CoreLocation
import Foundation
import WeatherKit

struct WeatherService {
    private let service = WeatherKit.WeatherService.shared

    func currentWeather(at location: CLLocation) async throws -> WeatherSnapshot {
        let weather = try await service.weather(for: location, including: .current)
        let temperature = weather.temperature
        let kind: WeatherSnapshot.Kind

        switch weather.condition {
        case .rain, .drizzle, .heavyRain, .freezingDrizzle, .freezingRain, .sunShowers, .scatteredThunderstorms, .strongStorms, .thunderstorms:
            kind = .wet
        case .snow, .blizzard, .blowingSnow, .flurries, .heavySnow, .sleet, .sunFlurries, .wintryMix:
            kind = .snow
        case .clear, .mostlyClear, .partlyCloudy:
            kind = temperature.converted(to: .celsius).value > 30 ? .hot : .clear
        case .cloudy, .foggy, .haze, .mostlyCloudy, .smoky:
            kind = .cloudy
        default:
            kind = temperature.converted(to: .celsius).value < 5 ? .cold : .unknown
        }

        return WeatherSnapshot(
            temperature: temperature,
            conditionText: weather.condition.description,
            symbolName: weather.symbolName,
            kind: kind
        )
    }
}
