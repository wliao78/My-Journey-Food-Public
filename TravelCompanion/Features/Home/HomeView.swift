import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locationService = LocationService()
    @StateObject private var model = HomeViewModel()
    @StateObject private var speech = SpeechInputService()
    @Query private var feedback: [PlaceFeedback]
    @State private var showingSettings = false
    @State private var showingWeatherDiagnostic = false
    @State private var isAtBottom = false
    @State private var pendingAutomaticRefresh = false
    @State private var automaticRefreshInFlight = false
    @State private var wasBackgrounded = false
    @State private var didRequestLaunchRefresh = false
    @FocusState private var inputFocused: Bool

    private var items: [Recommendation] {
        guard model.recommendationTravelMode == model.travelMode else { return [] }
        return Array((model.recommendations[.eat] ?? []).prefix(6))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusHeader
                modePicker
                statusMessage
                recommendationList
            }
            .background { FoodTheme.background }
            .foregroundStyle(.white)
            .tint(FoodTheme.accent)
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                if let destination = items.first(where: { $0.id == id }) {
                    PlaceDetailView(recommendation: destination, currentLocation: locationService.location)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBubble }
            .sheet(isPresented: $showingSettings, onDismiss: { requestAutomaticRefresh() }) { SettingsView() }
            .alert(String(localized: "天气暂不可用"), isPresented: $showingWeatherDiagnostic) {
                Button(String(localized: "确定"), role: .cancel) { }
            } message: {
                Text(model.weatherErrorMessage ?? String(localized: "请稍后重试。"))
            }
            .task {
                guard !didRequestLaunchRefresh else { return }
                didRequestLaunchRefresh = true
                requestAutomaticRefresh()
            }
            .onChange(of: locationService.location) { _, location in
                Task { await model.refreshWeather(at: location) }
                startAutomaticRefreshIfPossible()
            }
            .onChange(of: model.travelMode) { _, _ in
                requestAutomaticRefresh()
            }
            .onChange(of: model.isLoading) { _, loading in
                if !loading { startAutomaticRefreshIfPossible() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { wasBackgrounded = true }
                if phase == .active, wasBackgrounded {
                    wasBackgrounded = false
                    requestAutomaticRefresh()
                }
            }
            .onChange(of: speech.transcript) { _, transcript in
                if !transcript.isEmpty { model.context = transcript }
            }
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "MY JOURNEY"))
                .font(.caption2.bold())
                .tracking(2.5)
                .foregroundStyle(FoodTheme.accent)
            HStack(alignment: .center) {
                    Text(String(localized: "我的旅程 — 吃喝"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer(minLength: 8)
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.subheadline)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.13), in: Circle())
                }
                .accessibilityLabel(String(localized: "设置"))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundStyle(FoodTheme.accent)
                Text(PublicDemo.enabled ? PublicDemo.title : locationService.placeName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button { showingWeatherDiagnostic = true } label: {
                    Label(weatherText, systemImage: model.weather.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(model.weatherErrorMessage == nil)
                .accessibilityLabel(model.weatherErrorMessage == nil ? weatherText : String(localized: "天气未知，点击查看原因"))
            }
        }
        .padding(16)
        .foodPanel()
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var weatherText: String {
        model.weather == .unavailable
            ? String(localized: "天气未知")
            : "\(model.weather.temperature.value.formatted(.number.precision(.fractionLength(1))))°"
    }

    private var modePicker: some View {
        Picker(String(localized: "出行方式"), selection: $model.travelMode) {
            ForEach(TravelMode.allCases) { mode in
                Label(mode.title, systemImage: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var statusMessage: some View {
        if model.isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.loadingMessage)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .foregroundStyle(FoodTheme.secondaryText)
            .padding(.bottom, 8)
        } else if let message = model.errorMessage ?? locationService.errorMessage ?? speech.errorMessage {
            Text(message)
                .font(.footnote)
            .foregroundStyle(FoodTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            .padding(.bottom, 8)
        } else if model.isShowingCachedResults {
            Text(String(localized: "正在显示上次推荐"))
                .font(.footnote)
            .foregroundStyle(FoodTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var recommendationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "为你精选"))
                            .font(.title3.bold())
                        Text(String(format: NSLocalizedString("附近吃喝 · %@ 个地点", comment: ""), String(describing: items.count)))
                            .font(.caption)
                            .foregroundStyle(FoodTheme.secondaryText)
                    }
                    Spacer()
                    Button {
                        Task { await resetAndRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .disabled(model.isLoading)
                    .accessibilityLabel(String(localized: "清除条件并刷新吃喝推荐"))
                }
                .padding(.bottom, 4)

                if items.isEmpty && APIKeyStore().load() == nil && !model.isLoading {
                    Text(String(localized: "演示推荐 · 非真实店铺"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(FoodTheme.accent)
                    ForEach(0..<6, id: \.self) { index in
                        HStack(spacing: 12) {
                            Image(systemName: ["birthday.cake", "cup.and.saucer", "fork.knife", "takeoutbag.and.cup.and.straw", "wineglass", "leaf"][index])
                                .frame(width: 32)
                                .foregroundStyle(FoodTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(demoTitles[index]).font(.headline)
                                Text(String(localized: "设置服务商与位置后，才会搜索真实地点并核对条件。"))
                                    .font(.caption).foregroundStyle(FoodTheme.secondaryText)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .foodPanel()
                    }
                } else if items.isEmpty {
                    ContentUnavailableView(
                        model.isLoading ? String(localized: "正在寻找附近餐饮") : String(localized: "暂无推荐"),
                        systemImage: "fork.knife",
                        description: Text(model.isLoading ? String(localized: "正在根据位置和条件筛选") : String(localized: "点击刷新，或输入想吃喝的内容"))
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item.id) {
                            RecommendationCard(
                                recommendation: item,
                                position: index + 1,
                                count: items.count,
                                myReview: feedback.filter { $0.mapItemIdentifier == item.id }
                                    .max(by: { $0.createdAt < $1.createdAt })?.note
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Text(String(localized: "已到最后一条 · 继续上拉刷新"))
                        .font(.footnote)
                        .foregroundStyle(FoodTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }.defaultScrollAnchor(PublicLanguage.qaScrollBottom ? .bottom : .top)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let remaining = geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
            return remaining <= 12
        } action: { _, atBottom in
            isAtBottom = atBottom
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 25).onEnded { gesture in
                guard isAtBottom, gesture.translation.height < -65, !model.isLoading, !items.isEmpty else { return }
                Task { await refreshRecommendations() }
            }
        )
        .accessibilityIdentifier("foodRecommendationScroll")
    }

    private var demoTitles: [String] {
        [String(localized: "街区面包店"), String(localized: "独立咖啡馆"),
         String(localized: "家常小餐馆"), String(localized: "当地市场小吃"),
         String(localized: "晚餐与葡萄酒"), String(localized: "清爽素食选择")]
    }

    private var inputBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "fork.knife")
                .font(.subheadline.weight(.semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(FoodTheme.accent)
                .accessibilityLabel(String(localized: "吃喝"))
            TextField(String(localized: "想吃什么或喝什么？"), text: $model.context, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { Task { await submitRequest() } }
                .accessibilityLabel(String(localized: "补充吃喝推荐条件"))
            Button {
                inputFocused = false
                if speech.isListening { speech.stop() }
                else { Task { await speech.start() } }
            } label: {
                Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(speech.isListening ? String(localized: "停止听写") : String(localized: "开始听写"))
            Button { Task { await submitRequest() } } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(model.isLoading || model.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(String(localized: "提交吃喝条件"))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(FoodTheme.border))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func submitRequest() async {
        inputFocused = false
        speech.stop()
        if locationService.location == nil { locationService.requestLocation() }
        await model.submitRequest(for: .eat, location: locationService.location, feedback: feedback)
    }

    private func refreshRecommendations() async {
        await model.refresh(.eat, location: locationService.location, feedback: feedback)
    }

    private func requestAutomaticRefresh() {
        if PublicDemo.enabled { model.loadDemo(); return }
        pendingAutomaticRefresh = true
        if locationService.location == nil { locationService.requestLocation() }
        startAutomaticRefreshIfPossible()
    }

    private func startAutomaticRefreshIfPossible() {
        guard pendingAutomaticRefresh, !automaticRefreshInFlight,
              !model.isLoading,
              locationService.location != nil else { return }
        pendingAutomaticRefresh = false
        automaticRefreshInFlight = true
        Task {
            await refreshRecommendations()
            automaticRefreshInFlight = false
            startAutomaticRefreshIfPossible()
        }
    }

    private func resetAndRefresh() async {
        inputFocused = false
        speech.stop()
        if locationService.location == nil { locationService.requestLocation() }
        await model.resetAndRefresh(.eat, location: locationService.location, feedback: feedback)
    }
}

private struct RecommendationCard: View {
    let recommendation: Recommendation
    let position: Int
    let count: Int
    let myReview: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PlacePreviewImage(mapItem: recommendation.mapItem)
                .frame(width: 88, height: 88)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(recommendation.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(position)/\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(FoodTheme.accent)
                }
                Text(PublicDemo.enabled ? PublicDemo.title : recommendation.formattedDistance + " · " + recommendation.formattedTravelTime)
                    .font(.caption)
                    .foregroundStyle(FoodTheme.secondaryText)
                Text(recommendation.reason)
                    .font(.caption)
                    .lineLimit(2)
                if !recommendation.suggestion.isEmpty {
                    Text(recommendation.suggestion)
                        .font(.caption2)
                        .foregroundStyle(FoodTheme.secondaryText)
                        .lineLimit(2)
                }
                if let myReview, !myReview.isEmpty {
                    Text(String(format: NSLocalizedString("我的评价：%@", comment: ""), String(describing: myReview)))
                        .font(.caption2)
                        .foregroundStyle(FoodTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foodPanel(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}
