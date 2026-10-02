import CoreLocation
import Foundation
import MapKit

struct RecommendationCache: Codable {
    let savedAt: Date
    let latitude: Double
    let longitude: Double
    let items: [CachedRecommendation]
}

struct CachedRecommendation: Codable {
    let placeID: String
    let title: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
    let phoneNumber: String?
    let url: URL?
    let category: RecommendationCategory
    let travelMode: TravelMode
    let travelTime: TimeInterval?
    let distance: CLLocationDistance
    let score: Double
    let reason: String
    let suggestion: String?

    init(_ recommendation: Recommendation) {
        placeID = recommendation.id
        let coordinate = recommendation.mapItem.placemark.coordinate
        title = recommendation.title
        subtitle = recommendation.subtitle
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        phoneNumber = recommendation.mapItem.phoneNumber
        url = recommendation.mapItem.url
        category = recommendation.category
        travelMode = recommendation.travelMode
        travelTime = recommendation.travelTime
        distance = recommendation.distance
        score = recommendation.score
        reason = recommendation.reason
        suggestion = recommendation.suggestion
    }

    var recommendation: Recommendation {
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
        let item = MKMapItem(placemark: placemark)
        item.name = title
        item.phoneNumber = phoneNumber
        item.url = url
        return Recommendation(
            mapItem: item,
            category: category,
            travelMode: travelMode,
            travelTime: travelTime,
            distance: distance,
            score: score,
            reason: reason,
            suggestion: suggestion ?? "",
            cachedSubtitle: subtitle,
            identityOverride: placeID
        )
    }
}
