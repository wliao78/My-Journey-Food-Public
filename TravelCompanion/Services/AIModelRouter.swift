import Foundation
import OSLog

enum AIConfig {
    static let defaultModel = "gpt-6-luna"
    static let escalationModel = "gpt-6-sol"
    static let reservedModel = "gpt-6-astra"
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
}

struct AICandidate: Codable {
    let placeID: String
    let name: String
    let category: String
    let distanceMeters: Double
    let travelMinutes: Int?
    let appleCategory: String?
    let address: String
    let matchedSearchQueries: [String]
}

struct AIContext: Codable {
    let latitude: Double
    let longitude: Double
    let localTime: String
    let weather: String
    let travelMode: String
    let category: String
    let userRequest: String
    let reviews: [String]
    let candidates: [AICandidate]
}

struct AIRankedPlace: Codable {
    let placeID: String
    let rank: Int
    let reason: String
    let suggestion: String
}

private struct AIRanking: Codable {
    let places: [AIRankedPlace]
}

private struct FoodSearchQueries: Codable {
    let queries: [String]
}

enum AIRecommendationError: LocalizedError {
    case missingKey, invalidResponse, rejectedResult, requestFailed(Int), networkUnavailable

    var errorDescription: String? {
        switch self {
        case .missingKey: String(localized: "请先在设置中填写所选服务商的 API Key。")
        case .invalidResponse: String(localized: "AI 回复无法读取，请重试。")
        case .rejectedResult: String(localized: "AI 推荐未通过校验，已保留上次结果；请重试。")
        case .requestFailed(let code): String(format: NSLocalizedString("AI 连接失败（%lld），请检查密钥和网络。", comment: "AI HTTP error"), code)
        case .networkUnavailable: String(localized: "网络暂时不可用，已保留上次推荐。")
        }
    }
}

@MainActor
final class AIModelRouter {
    private var keyStore: APIKeyStore { APIKeyStore() }
    private let logger = Logger(subsystem: "com.myjourney.public.food", category: "AIModelRouter")

    func testConnection() async throws {
        guard let key = keyStore.load(), !key.isEmpty else { throw AIRecommendationError.missingKey }
        let response: URLResponse
        do {
            (_, response) = try await PublicAITransport.send(
                body: ["model": AIConfig.defaultModel, "instructions": "Reply briefly.", "input": "ping", "max_output_tokens": 20],
                key: key, timeout: 20)
        }
        catch { throw AIRecommendationError.networkUnavailable }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AIRecommendationError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func rank(_ context: AIContext) async throws -> [AIRankedPlace] {
        guard let key = keyStore.load(), !key.isEmpty else { throw AIRecommendationError.missingKey }
        guard !PublicDemo.enabled else {
            throw NSError(domain: "OfflineDemo", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "演示模式不会处理你的输入，请关闭演示模式以获取真实 AI 结果。")])
        }
        guard PublicAIConsent.granted else {
            throw NSError(domain: "AIConsent", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "请先在设置中同意向所选 AI 服务商发送资料。")])
        }
        let complex = context.userRequest.count > 50 || context.userRequest.contains("但是") || context.userRequest.contains("同时")
        if !complex {
            do {
                let luna = try await requestRanking(context, model: AIConfig.defaultModel, key: key, escalated: false)
                if !luna.isEmpty { return luna }
                return (try? await requestRanking(context, model: AIConfig.escalationModel, key: key, escalated: true)) ?? luna
            }
            catch { logger.notice("Luna request or validation failed; escalating to Sol") }
        }
        return try await requestRanking(context, model: AIConfig.escalationModel, key: key, escalated: true)
    }

    func searchQueries(for requestText: String) async throws -> [String] {
        guard let key = keyStore.load(), !key.isEmpty else { throw AIRecommendationError.missingKey }
        guard PublicAIConsent.granted else { return [] }
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "properties": ["queries": ["type": "array", "items": ["type": "string"]]],
            "required": ["queries"]
        ]
        var body: [String: Any] = [
            "model": AIConfig.defaultModel,
            "store": false,
            "max_output_tokens": 600,
            "reasoning": ["effort": "low"],
            "instructions": "把用户的餐饮要求变成最多四个适合 Apple Maps 搜索的简短英文关键词，按最精确到较宽泛排序。翻译菜品、菜系或餐厅类型；不要把‘附近’‘步行’‘便宜’‘安静’‘现在’等距离、方式、价格、氛围或时间条件混入搜索词，也不要臆造具体店名。用户没指定菜品或类型时返回空数组。只输出 JSON。",
            "input": requestText,
            "text": ["format": ["type": "json_schema", "name": "food_search_queries", "strict": true, "schema": schema]]
        ]
        body["instructions"] = (body["instructions"] as? String ?? "") +
            "\nReturn English search keywords regardless of the user's input language."
        let (data, response) = try await PublicAITransport.send(body: body, key: key, timeout: 25)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AIRecommendationError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "completed",
              let output = json["output"] as? [[String: Any]],
              let message = output.first(where: { $0["type"] as? String == "message" }),
              let content = message["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "output_text" })?["text"] as? String,
              let result = try? JSONDecoder().decode(FoodSearchQueries.self, from: Data(text.utf8)) else {
            throw AIRecommendationError.invalidResponse
        }
        var seen: Set<String> = []
        return Array(result.queries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 80 && seen.insert($0.lowercased()).inserted }
            .prefix(4))
    }

    private func requestRanking(_ context: AIContext, model: String, key: String, escalated: Bool) async throws -> [AIRankedPlace] {
        let inputData = try JSONEncoder().encode(context)
        let input = String(decoding: inputData, as: UTF8.self)
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "properties": ["places": [
                "type": "array", "items": [
                    "type": "object", "additionalProperties": false,
                    "properties": [
                        "placeID": ["type": "string"],
                        "rank": ["type": "integer"],
                        "reason": ["type": "string"],
                        "suggestion": ["type": "string"]
                    ],
                    "required": ["placeID", "rank", "reason", "suggestion"]
                ]
            ]],
            "required": ["places"]
        ]
        var body: [String: Any] = [
            "model": model,
            "store": false,
            "max_output_tokens": 2_200,
            "reasoning": ["effort": "low"],
            "instructions": "你是附近餐饮推荐排序器。只从候选餐厅、咖啡馆、面包店或酿酒馆中选0到6个不同地点；有六个可靠匹配时尽量给满六个，但不要为了凑数推荐不符合用户明确要求的地点，没有可靠匹配就返回空 places。用户要求的菜系或餐饮类型是硬条件，可以参考地点名称、类别和 matchedSearchQueries 地图搜索命中词判断相关性；搜索命中只是线索，不证明菜单有某道菜。用户要求具体菜品时，只有地点名称或提供的类别能够支持才推荐，不能根据普通餐厅类别或搜索命中推断一定供应牛排等指定菜品。placeID 必须逐字复制候选的短编号（如 p0），不能输出真实地图 ID。满足硬条件后再考虑出行方式、时间、天气与个人评价。绝不编造地点、菜单或营业状态。已明确关闭的地点不能选。reason 每条一句简短的当前应用语言，说明与要求的关联。suggestion 用两句当前应用语言给出实用建议；不得声称店内一定有未验证的菜、它是招牌菜或有价格。使用‘可以考虑’‘可先看看’之类的建议语气。严格按名次从1开始输出。",
            "input": input,
            "text": ["format": ["type": "json_schema", "name": "travel_ranking", "strict": true, "schema": schema]]
        ]
        body["instructions"] = (body["instructions"] as? String ?? "") +
            (PublicLanguage.isChinese
                ? "\nUse Simplified Chinese for reason and suggestion."
                : "\nUse natural English for reason and suggestion, even though these instructions are Chinese.")
        let started = Date()
        let data: Data
        let response: URLResponse
        do { (data, response) = try await PublicAITransport.send(body: body, key: key, timeout: 35) }
        catch {
            logger.error("model=\(model, privacy: .public) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000)) escalated=\(escalated) validated=false network_error")
            throw AIRecommendationError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            logger.error("model=\(model, privacy: .public) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000)) escalated=\(escalated) validated=false http_error")
            throw AIRecommendationError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "completed",
              let output = json["output"] as? [[String: Any]],
              let message = output.first(where: { $0["type"] as? String == "message" }),
              let content = message["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "output_text" })?["text"] as? String,
              let ranking = try? JSONDecoder().decode(AIRanking.self, from: Data(text.utf8)) else {
            throw AIRecommendationError.invalidResponse
        }
        let validIDs = Set(context.candidates.map(\.placeID))
        var seenIDs: Set<String> = []
        let selected = ranking.places.sorted { $0.rank < $1.rank }
            .filter { choice in
                guard validIDs.contains(choice.placeID),
                      !choice.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !choice.suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                return seenIDs.insert(choice.placeID).inserted
            }
            .prefix(6)
            .enumerated()
            .map { index, choice in
                AIRankedPlace(placeID: choice.placeID, rank: index + 1, reason: choice.reason, suggestion: choice.suggestion)
            }
        guard !selected.isEmpty || ranking.places.isEmpty else {
            logger.error("model=\(model, privacy: .public) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000)) escalated=\(escalated) validated=false rules_error")
            throw AIRecommendationError.rejectedResult
        }
        let usage = json["usage"] as? [String: Any] ?? [:]
        logger.info("model=\(model, privacy: .public) input_tokens=\(usage["input_tokens"] as? Int ?? 0) output_tokens=\(usage["output_tokens"] as? Int ?? 0) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000)) escalated=\(escalated) validated=true")
        return selected
    }
}
