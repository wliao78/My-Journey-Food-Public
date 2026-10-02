import CoreLocation
import Foundation
import MapKit
import OSLog

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var travelMode: TravelMode = .walking
    @Published var context = ""
    @Published private(set) var weather = WeatherSnapshot.unavailable
    @Published private(set) var weatherErrorMessage: String?
    @Published private(set) var recommendations: [RecommendationCategory: [Recommendation]] = [:]
    @Published private(set) var recommendationTravelMode: TravelMode = .walking
    @Published private(set) var isLoading = false
    @Published private(set) var loadingCategory: RecommendationCategory?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isShowingCachedResults = false
    @Published private(set) var loadingMessage = String(localized: "正在重新推荐…")

    private let weatherService = WeatherService()
    private let recommendationService = RecommendationService()
    private let cacheService = RecommendationCacheService()
    private let logger = Logger(subsystem: "com.myjourney.public.food", category: "Weather")
    private var categoryContexts: [RecommendationCategory: String] = [:]

    init() {
        recommendations = cacheService.loadRecommendations()
        isShowingCachedResults = !recommendations.isEmpty
        if APIKeyStore().load() == nil {
            errorMessage = AIRecommendationError.missingKey.localizedDescription
        }
    }

    func submitRequest(for category: RecommendationCategory, location: CLLocation?, feedback: [PlaceFeedback]) async {
        let draft = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }
        if draft.hasPrefix("sk-") {
            context = ""
            errorMessage = String(localized: "检测到 API Key；已清空输入内容，请只在设置页填写密钥。")
            return
        }
        guard location != nil else {
            errorMessage = String(localized: "正在获取当前位置，请稍后再发送。")
            return
        }
        guard !isLoading else { return }
        context = ""
        categoryContexts[category] = draft
        await refresh(category, location: location, feedback: feedback)
    }

    func refresh(_ category: RecommendationCategory, location: CLLocation?, feedback: [PlaceFeedback]) async {
        guard let location else { return }
        guard !isLoading else { return }
        guard APIKeyStore().load() != nil else {
            errorMessage = AIRecommendationError.missingKey.localizedDescription
            await updateWeather(at: location)
            return
        }
        let feedbackSignals = feedback.map {
            FeedbackSignal(mapItemIdentifier: $0.mapItemIdentifier, note: $0.note)
        }
        let requestedMode = travelMode
        loadingCategory = category
        isLoading = true
        loadingMessage = String(format: NSLocalizedString("正在更新%@推荐…", comment: "Refreshing a recommendation category"), category.title)
        errorMessage = nil

        await updateWeather(at: location)
        do {
            let values = try await recommendationService.recommendations(
                category: category,
                near: location,
                travelMode: requestedMode,
                weather: weather,
                context: categoryContexts[category] ?? "",
                feedback: feedbackSignals
            )
            if travelMode == requestedMode {
                recommendations[category] = values
                recommendationTravelMode = requestedMode
                if values.isEmpty {
                    errorMessage = String(format: NSLocalizedString("扩大搜索范围后仍未找到符合条件的%@地点；可清除条件并单独刷新。", comment: "No matching places"), category.title)
                }
                cacheService.save(recommendations, near: location)
                isShowingCachedResults = false
            }
        } catch {
            if travelMode == requestedMode {
                if (error as NSError).domain == MKError.errorDomain {
                    errorMessage = String(localized: "地图服务暂时无法搜索吃喝地点，请稍后刷新。已有推荐仍可查看。")
                } else {
                    errorMessage = error.localizedDescription
                }
                isShowingCachedResults = !recommendations.isEmpty
            }
        }
        isLoading = false
        loadingCategory = nil
    }

    func resetAndRefresh(_ category: RecommendationCategory, location: CLLocation?, feedback: [PlaceFeedback]) async {
        categoryContexts[category] = ""
        await refresh(category, location: location, feedback: feedback)
    }

    func refreshWeather(at location: CLLocation?) async {
        guard let location else { return }
        await updateWeather(at: location)
    }

    private func updateWeather(at location: CLLocation) async {
        do {
            weather = try await weatherService.currentWeather(at: location)
            weatherErrorMessage = nil
        } catch {
            weather = .unavailable
            let failure = error as NSError
            weatherErrorMessage = String(localized: "天气暂不可用，请稍后重试。")
            logger.error("WeatherKit failed domain=\(failure.domain, privacy: .public) code=\(failure.code) description=\(error.localizedDescription, privacy: .public)")
        }
    }
}
