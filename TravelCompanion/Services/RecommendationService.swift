import CoreLocation
import Foundation
import MapKit

struct FeedbackSignal: Sendable {
    let mapItemIdentifier: String
    let note: String
}

private struct MapSearchResults {
    let items: [MKMapItem]
    let preferredIDs: Set<String>
    let matchedQueries: [String: Set<String>]
}

@MainActor
struct RecommendationService {
    private let router = AIModelRouter()

    func recommendations(
        category: RecommendationCategory,
        near location: CLLocation,
        travelMode: TravelMode,
        weather: WeatherSnapshot,
        context: String,
        feedback: [FeedbackSignal]
    ) async throws -> [Recommendation] {
        let wantsNear = ["近", "附近", "不要太远", "near", "close"].contains { context.localizedCaseInsensitiveContains($0) }
        let initialDistance: CLLocationDistance = travelMode == .walking
            ? (wantsNear ? 2_000 : 5_000)
            : (wantsNear ? 8_000 : 20_000)
        let radiusLimit: CLLocationDistance = travelMode == .walking ? 20_000 : 50_000
        let distances = [initialDistance, min(initialDistance * 2, radiusLimit),
                         min(initialDistance * 4, radiusLimit)]
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchTerms: [String]
        if trimmedContext.isEmpty {
            searchTerms = []
        } else {
            searchTerms = (try? await router.searchQueries(for: trimmedContext)) ?? fallbackSearchTerms(for: trimmedContext)
        }
        var best: [Recommendation] = []
        var lastError: Error?
        for distance in Array(Set(distances)).sorted() {
            do {
                let matches = try await recommendations(
                    category: category, near: location, travelMode: travelMode,
                    weather: weather, context: context, searchTerms: searchTerms,
                    feedback: feedback, radius: distance
                )
                if matches.count > best.count { best = matches }
                if matches.count >= 6 { return matches }
            } catch {
                lastError = error
            }
        }
        if best.isEmpty, let lastError { throw lastError }
        return best
    }

    private func recommendations(
        category: RecommendationCategory,
        near location: CLLocation,
        travelMode: TravelMode,
        weather: WeatherSnapshot,
        context: String,
        searchTerms: [String],
        feedback: [FeedbackSignal],
        radius maximumDistance: CLLocationDistance
    ) async throws -> [Recommendation] {
        let searchResults = try await search(category: category, near: location, searchTerms: searchTerms, radius: maximumDistance)
        let availableItems = searchResults.preferredIDs.isEmpty ? searchResults.items : searchResults.items.filter {
            searchResults.preferredIDs.contains(Recommendation.identity(for: $0))
        }
        let filtered = availableItems.compactMap { item -> (MKMapItem, CLLocationDistance)? in
            guard let point = item.placemark.location, isEligible(item, category: category) else { return nil }
            let distance = location.distance(from: point)
            guard distance <= maximumDistance else { return nil }
            return (item, distance)
        }
        .sorted {
            let leftPreferred = searchResults.preferredIDs.contains(Recommendation.identity(for: $0.0))
            let rightPreferred = searchResults.preferredIDs.contains(Recommendation.identity(for: $1.0))
            if leftPreferred != rightPreferred { return leftPreferred }
            return $0.1 < $1.1
        }

        var candidates: [Recommendation] = []
        for (item, distance) in filtered.prefix(100) {
            candidates.append(Recommendation(
                mapItem: item, category: category, travelMode: travelMode,
                travelTime: nil, distance: distance, score: 0,
                reason: "正在根据你的条件筛选…"
            ))
        }
        guard !candidates.isEmpty else { return [] }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        let candidatePairs = candidates.enumerated().map { ("p\($0.offset)", $0.element) }
        let aiInput = AIContext(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            localTime: formatter.string(from: .now),
            weather: weather.conditionText,
            travelMode: travelMode.rawValue,
            category: category.rawValue,
            userRequest: context,
            reviews: feedback.map { $0.note }.filter { !$0.isEmpty }.prefix(12).map { String($0.prefix(300)) },
            candidates: candidatePairs.map { token, candidate in
                AICandidate(
                    placeID: token, name: candidate.title, category: category.rawValue,
                    distanceMeters: candidate.distance,
                    travelMinutes: candidate.travelTime.map { Int(($0 / 60).rounded()) },
                    appleCategory: candidate.mapItem.pointOfInterestCategory?.rawValue,
                    address: candidate.subtitle,
                    matchedSearchQueries: Array(searchResults.matchedQueries[candidate.id] ?? []).sorted()
                )
            }
        )
        let ranked = try await router.rank(aiInput)
        let byID = Dictionary(uniqueKeysWithValues: candidatePairs)
        var selected: [Recommendation] = []
        for choice in ranked {
            guard let item = byID[choice.placeID] else { continue }
            let eta = await routeETA(from: location, to: item.mapItem, mode: travelMode)
            selected.append(Recommendation(
                mapItem: item.mapItem, category: item.category, travelMode: travelMode,
                travelTime: eta, distance: item.distance,
                score: Double(5 - choice.rank), reason: choice.reason,
                suggestion: choice.suggestion
            ))
        }
        return selected
    }

    private func isEligible(_ item: MKMapItem, category: RecommendationCategory) -> Bool {
        let name = item.name?.lowercased() ?? ""
        guard !["permanently closed", "temporarily closed", "closed", "已关闭", "已停业", "永久停业"].contains(where: name.contains) else { return false }
        guard let poi = item.pointOfInterestCategory else { return false }
        let accepted: Set<MKPointOfInterestCategory> = [.restaurant, .cafe, .bakery, .brewery]
        return accepted.contains(poi)
    }

    private func fallbackSearchTerms(for context: String) -> [String] {
        let mappings: [(String, String)] = [
            ("牛排", "steakhouse"), ("寿司", "sushi"), ("拉面", "ramen"),
            ("火锅", "hot pot"), ("川菜", "Sichuan restaurant"),
            ("粤菜", "Cantonese restaurant"), ("中餐", "Chinese restaurant"),
            ("日本", "Japanese restaurant"), ("日式", "Japanese restaurant"),
            ("韩餐", "Korean restaurant"), ("意大利", "Italian restaurant"),
            ("墨西哥", "Mexican restaurant"), ("咖啡", "coffee shop"),
            ("早午餐", "brunch"), ("面包", "bakery")
        ]
        let matches = mappings.filter { context.localizedCaseInsensitiveContains($0.0) }.map(\.1)
        if !matches.isEmpty { return matches }
        return context.range(of: "\\p{Han}", options: .regularExpression) == nil ? [context] : []
    }

    private func search(category: RecommendationCategory, near location: CLLocation, searchTerms: [String],
                        radius: CLLocationDistance) async throws -> MapSearchResults {
        var results: [String: MKMapItem] = [:]
        var preferredIDs: Set<String> = []
        var matchedQueries: [String: Set<String>] = [:]
        var lastError: Error?
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        let request = MKLocalSearch.Request()
        request.region = region
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including:
            [.restaurant, .cafe, .bakery, .brewery]
        )
        do {
            for item in try await MKLocalSearch(request: request).start().mapItems {
                results[Recommendation.identity(for: item)] = item
            }
        } catch { lastError = error }

        let queries = searchTerms.isEmpty ? ["restaurants", "local food"] : searchTerms + ["restaurants"]
        for (index, query) in queries.enumerated() {
            let search = MKLocalSearch.Request()
            search.naturalLanguageQuery = query
            search.region = region
            search.resultTypes = .pointOfInterest
            do {
                for item in try await MKLocalSearch(request: search).start().mapItems {
                    let id = Recommendation.identity(for: item)
                    results[id] = item
                    if index < searchTerms.count {
                        preferredIDs.insert(id)
                        matchedQueries[id, default: []].insert(query)
                    }
                }
            } catch { lastError = error }
        }
        do {
            let gridQuery = searchTerms.first ?? "restaurants"
            let step = radius / 2 / 111_000
            let longitudeScale = max(0.2, cos(location.coordinate.latitude * .pi / 180))
            var additionalSearches = 0
            gridSearch: for row in -2...2 {
                for column in -2...2 {
                    if row == 0 && column == 0 { continue }
                    if additionalSearches >= 4 { break gridSearch }
                    if (searchTerms.isEmpty ? results.count : preferredIDs.count) >= 100 { break gridSearch }
                    let center = CLLocationCoordinate2D(
                        latitude: location.coordinate.latitude + Double(row) * step,
                        longitude: location.coordinate.longitude + Double(column) * step / longitudeScale
                    )
                    let search = MKLocalSearch.Request()
                    search.naturalLanguageQuery = gridQuery
                    search.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 0.8,
                                                       longitudinalMeters: radius * 0.8)
                    search.resultTypes = .pointOfInterest
                    additionalSearches += 1
                    do {
                        for item in try await MKLocalSearch(request: search).start().mapItems {
                            let id = Recommendation.identity(for: item)
                            results[id] = item
                            if !searchTerms.isEmpty {
                                preferredIDs.insert(id)
                                matchedQueries[id, default: []].insert(gridQuery)
                            }
                        }
                    } catch { lastError = error }
                }
            }
        }
        if results.isEmpty, let lastError { throw lastError }
        return MapSearchResults(items: Array(results.values), preferredIDs: preferredIDs,
                                matchedQueries: matchedQueries)
    }

    private func routeETA(from location: CLLocation, to item: MKMapItem, mode: TravelMode) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = item
        request.transportType = mode.transportType
        return try? await MKDirections(request: request).calculateETA().expectedTravelTime
    }
}
