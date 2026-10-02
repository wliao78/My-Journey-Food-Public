import CoreLocation
import Foundation
import MapKit

enum RecommendationCategory: String, CaseIterable, Identifiable, Codable {
    case eat

    var id: String { rawValue }
    var title: String { String(localized: "吃喝") }
    var symbol: String { "fork.knife" }
    var tintName: String { "orange" }
}

enum TravelMode: String, CaseIterable, Identifiable, Codable {
    case walking
    case driving

    var id: String { rawValue }
    var title: String { self == .walking ? String(localized: "步行") : String(localized: "驾车") }
    var symbol: String { self == .walking ? "figure.walk" : "car.fill" }
    var transportType: MKDirectionsTransportType { self == .walking ? .walking : .automobile }
}

struct Recommendation: Identifiable {
    let mapItem: MKMapItem
    let category: RecommendationCategory
    let travelMode: TravelMode
    let travelTime: TimeInterval?
    let distance: CLLocationDistance
    let score: Double
    let reason: String
    let suggestion: String
    let cachedSubtitle: String?
    let identityOverride: String?

    init(
        mapItem: MKMapItem,
        category: RecommendationCategory,
        travelMode: TravelMode,
        travelTime: TimeInterval?,
        distance: CLLocationDistance,
        score: Double,
        reason: String,
        suggestion: String = "",
        cachedSubtitle: String? = nil,
        identityOverride: String? = nil
    ) {
        self.mapItem = mapItem
        self.category = category
        self.travelMode = travelMode
        self.travelTime = travelTime
        self.distance = distance
        self.score = score
        self.reason = reason
        self.suggestion = suggestion
        self.cachedSubtitle = cachedSubtitle
        self.identityOverride = identityOverride
    }

    var id: String {
        identityOverride ?? Self.identity(for: mapItem)
    }

    static func identity(for item: MKMapItem) -> String {
        if let identifier = item.identifier?.rawValue { return identifier }
        let coordinate = item.placemark.coordinate
        return "\(item.name ?? "place")|\(coordinate.latitude)|\(coordinate.longitude)"
    }

    var title: String { mapItem.name ?? String(localized: "未知地点") }

    var subtitle: String {
        cachedSubtitle ?? mapItem.placemark.title ?? String(localized: "附近")
    }

    var formattedTravelTime: String {
        guard let travelTime else { return String(localized: "时间未知") }
        return String(format: NSLocalizedString("%lld 分钟", comment: "Travel time in minutes"),
                      max(1, Int((travelTime / 60).rounded())))
    }

    var formattedDistance: String {
        Measurement(value: distance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
