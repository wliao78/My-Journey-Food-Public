import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct PlaceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var feedback: [PlaceFeedback]
    let recommendation: Recommendation
    let currentLocation: CLLocation?
    @StateObject private var speech = SpeechInputService()
    @State private var note = ""
    @State private var message: String?
    @FocusState private var reviewFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                imagery

                Text(String(localized: "餐厅详情"))
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundStyle(FoodTheme.accent)
                Text(recommendation.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(recommendation.reason)
                    .font(.body)
                    .foregroundStyle(FoodTheme.secondaryText)

                VStack(alignment: .leading, spacing: 5) {
                    Label(String(localized: "可以考虑的菜品"), systemImage: "fork.knife")
                        .font(.headline)
                    Text(recommendation.suggestion.isEmpty ? String(localized: "暂无菜品建议") : recommendation.suggestion)
                    Text(String(localized: "AI 建议，并非已核实菜单；请以店家实际供应为准。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let website = recommendation.mapItem.url {
                        Link(String(localized: "查看餐厅官网或菜单"), destination: website)
                    }
                }
                .padding(16)
                .foodPanel()

                VStack(alignment: .leading, spacing: 5) {
                    Label(String(localized: "营业时间和当前状态"), systemImage: "clock")
                        .font(.headline)
                    Text(String(localized: "请在 Apple 地图查看实时营业时间"))
                        .foregroundStyle(.secondary)
                    Button(String(localized: "在 Apple 地图查看")) { openMaps() }
                }
                .padding(16)
                .foodPanel()

                Label(recommendation.formattedDistance + " · " + recommendation.formattedTravelTime, systemImage: "location")
                    .font(.headline)
                    .foregroundStyle(FoodTheme.accent)

                HStack(alignment: .top) {
                    Text(recommendation.subtitle)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = recommendation.subtitle
                        message = String(localized: "地址已复制")
                    } label: { Label(String(localized: "复制"), systemImage: "doc.on.doc") }
                }
                .padding(16)
                .foodPanel()

                if PublicDemo.enabled {
                    Label(PublicDemo.notice, systemImage: "wifi.slash")
                        .padding().frame(maxWidth: .infinity)
                } else {
                Map(initialPosition: .region(region)) {
                    if let currentLocation {
                        Marker(String(localized: "我的位置"), systemImage: "location.fill", coordinate: currentLocation.coordinate)
                            .tint(.blue)
                    }
                    Marker(recommendation.title, coordinate: recommendation.mapItem.placemark.coordinate)
                        .tint(.orange)
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .onTapGesture { openMaps() }
                Button { openMaps() } label: {
                    Label(String(format: NSLocalizedString("在 Apple 地图中%@导航", comment: ""), String(describing: recommendation.travelMode.title)), systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                }

                reviewSection

                VStack(alignment: .leading, spacing: 5) {
                    Label(String(localized: "其他用户的代表评价"), systemImage: "person.2")
                        .font(.headline)
                    Text(String(localized: "当前数据源未提供可核实的用户评价"))
                        .foregroundStyle(.secondary)
                    Button(String(localized: "在 Apple 地图查看评价")) { openMaps() }
                }
                .padding(16)
                .foodPanel()

                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            .padding(16)
        }.defaultScrollAnchor(PublicLanguage.qaScrollBottom ? .bottom : .top)
        .scrollDismissesKeyboard(.interactively)
        .background { FoodTheme.background }
        .foregroundStyle(.white)
        .tint(FoodTheme.accent)
        .preferredColorScheme(.dark)
        .navigationTitle(recommendation.category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if reviewFocused {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "完成")) { reviewFocused = false }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: "完成")) { reviewFocused = false }
                }
            }
        }
        .onAppear { note = "" }
        .onDisappear { speech.stop() }
        .onChange(of: speech.transcript) { _, value in
            if speech.isListening, !value.isEmpty { note = value }
        }
    }

    private var imagery: some View {
        VStack(spacing: 6) {
            Button { openMaps() } label: {
                PlacePreviewImage(mapItem: recommendation.mapItem)
                    .frame(height: 220)
                    .clipped()
            }
            .buttonStyle(.plain)
            HStack(spacing: 6) {
                ForEach([60.0, -60.0, 120.0], id: \.self) { offset in
                    Button { openMaps() } label: {
                        PlacePreviewImage(mapItem: recommendation.mapItem, offsetMeters: offset)
                        .frame(height: 68)
                        .clipped()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityLabel(String(localized: "Apple 地图实景与三个地图预览，点击查看来源"))
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "我的评价"))
                .font(.title2.bold())
            ForEach(placeFeedback, id: \.id) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Text(entry.note)
                    Button(String(localized: "删除这条评价"), role: .destructive) {
                        modelContext.delete(entry)
                        do {
                            try modelContext.save()
                            message = String(localized: "评价已删除")
                        } catch { message = String(localized: "删除失败，请重试") }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .foodPanel(cornerRadius: 14)
            }
            Text(String(localized: "添加新评价"))
                .font(.subheadline.bold())
            TextEditor(text: $note)
                .frame(minHeight: 110)
                .padding(6)
                .scrollContentBackground(.hidden)
                .foodPanel(cornerRadius: 14)
                .focused($reviewFocused)
                .accessibilityLabel(String(localized: "输入我的评价"))
            HStack {
                Button(speech.isListening ? String(localized: "停止语音") : String(localized: "语音输入")) {
                    reviewFocused = false
                    if speech.isListening { speech.stop() }
                    else { Task { await speech.start() } }
                }
                .buttonStyle(.bordered)
                Button(String(localized: "保存评价")) { saveFeedback() }
                    .buttonStyle(.borderedProminent)
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error = speech.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .foodPanel()
    }

    private var placeFeedback: [PlaceFeedback] {
        feedback.filter { $0.mapItemIdentifier == recommendation.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var region: MKCoordinateRegion {
        let destination = recommendation.mapItem.placemark.coordinate
        guard let currentLocation else {
            return MKCoordinateRegion(center: destination, latitudinalMeters: 1_500, longitudinalMeters: 1_500)
        }
        let center = CLLocationCoordinate2D(
            latitude: (destination.latitude + currentLocation.coordinate.latitude) / 2,
            longitude: (destination.longitude + currentLocation.coordinate.longitude) / 2
        )
        return MKCoordinateRegion(
            center: center,
            latitudinalMeters: max(1_500, recommendation.distance * 2.5),
            longitudinalMeters: max(1_500, recommendation.distance * 2.5)
        )
    }

    private func openMaps() {
        guard !PublicDemo.enabled else { message = PublicDemo.notice; return }
        recommendation.mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: recommendation.travelMode == .walking
                ? MKLaunchOptionsDirectionsModeWalking
                : MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func saveFeedback() {
        reviewFocused = false
        speech.stop()
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return }
        let newFeedback = PlaceFeedback(
            mapItemIdentifier: recommendation.id,
            placeName: recommendation.title,
            note: trimmedNote
        )
        modelContext.insert(newFeedback)
        do {
            try modelContext.save()
            note = ""
            message = String(localized: "评价已保存")
        } catch {
            modelContext.delete(newFeedback)
            message = String(localized: "保存失败，请重试")
        }
    }
}
#if DEBUG
@MainActor
enum PublicLocalizationQA {
    static var screen: AnyView? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LocalizationQA"), args.indices.contains(index + 1) else { return nil }
        let route = args[index + 1]
        if route == "settings" { return AnyView(SettingsView()) }
        let model = HomeViewModel()
        model.loadDemo()
        guard let item = model.recommendations[.eat]?.first else { return nil }
        return AnyView(NavigationStack { PlaceDetailView(recommendation: item, currentLocation: nil) })
    }
}
#endif
