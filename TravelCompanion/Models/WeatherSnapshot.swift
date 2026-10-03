import Foundation

struct WeatherSnapshot: Equatable {
    enum Kind: Equatable {
        case clear, cloudy, wet, snow, hot, cold, unknown
    }

    let temperature: Measurement<UnitTemperature>
    let conditionText: String
    let symbolName: String
    let kind: Kind

    static let unavailable = WeatherSnapshot(
        temperature: .init(value: 0, unit: .celsius),
        conditionText: String(localized: "天气暂不可用"),
        symbolName: "cloud",
        kind: .unknown
    )
}
