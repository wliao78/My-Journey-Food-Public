import CoreLocation
import Foundation

struct RecommendationCacheService {
    private let key = "recommendation-cache-v1.1"
    private let defaults = UserDefaults.standard

    func load() -> RecommendationCache? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RecommendationCache.self, from: data)
    }

    func loadRecommendations() -> [RecommendationCategory: [Recommendation]] {
        guard let cache = load() else { return [:] }
        return Dictionary(grouping: cache.items.map(\.recommendation), by: \.category)
    }

    func save(_ recommendations: [RecommendationCategory: [Recommendation]], near location: CLLocation) {
        let items = RecommendationCategory.allCases.flatMap { category in
            (recommendations[category] ?? []).map(CachedRecommendation.init)
        }
        let cache = RecommendationCache(
            savedAt: .now,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            items: items
        )
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: key)
    }
}
