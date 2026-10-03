import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("publicAIProvider") private var providerID = PublicAIProvider.openAI.rawValue
    @State private var keyInput = ""
    @State private var hasSavedKey = APIKeyStore().load() != nil
    @State private var isTesting = false
    @State private var message: String?
    @State private var aiConsent = PublicAIConsent.granted

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(String(localized: "设置"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(String(localized: "智能推荐服务"))
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundStyle(FoodTheme.accent)
                    VStack(alignment: .leading, spacing: 14) {
                    Picker(String(localized: "AI 服务商"), selection: $providerID) {
                        ForEach(PublicAIProvider.allCases) { provider in
                            Text(provider.title).tag(provider.rawValue)
                        }
                    }
                    .onChange(of: providerID) { _, _ in
                        hasSavedKey = APIKeyStore().load() != nil
                        aiConsent = PublicAIConsent.granted
                        keyInput = ""
                        message = nil
                    }
                    Label(hasSavedKey ? String(localized: "密钥已保存") : String(localized: "添加 API 密钥"), systemImage: "key.fill")
                        .font(.headline)
                    PublicAIConfigurationView(provider: PublicAIProvider.selected)
                    SecureField(String(localized: "输入 API Key"), text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .padding(12)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    Button(String(localized: "保存密钥")) {
                        if APIKeyStore().save(keyInput) {
                            keyInput = ""
                            hasSavedKey = true
                            message = String(localized: "密钥已保存在本机钥匙串。")
                        } else { message = String(localized: "保存失败，请重试。") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(isTesting ? String(localized: "正在测试…") : String(localized: "测试连接")) {
                        Task {
                            isTesting = true
                            defer { isTesting = false }
                            do {
                                try await AIModelRouter().testConnection()
                                message = String(localized: "所选服务商连接成功。")
                            } catch { message = PublicLanguage.errorDescription(error) }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasSavedKey || isTesting)
                    Button(String(localized: "清除密钥"), role: .destructive) {
                        if APIKeyStore().clear() {
                            hasSavedKey = false
                            keyInput = ""
                            message = String(localized: "密钥已从本机删除。")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasSavedKey)
                    }
                    .padding(18)
                    .foodPanel()
                    VStack(alignment: .leading, spacing: 10) {
                    Label(String(localized: "隐私说明"), systemImage: "hand.raised.fill")
                        .font(.headline)
                    Text(String(localized: "密钥只保存在这台设备的钥匙串。推荐时，位置、时间、天气、输入条件和评价会发送给所选 AI 服务商。"))
                        .font(.footnote)
                    Toggle(String(localized: "同意向所选 AI 服务商发送资料"), isOn: $aiConsent)
                        .onChange(of: aiConsent) { _, value in PublicAIConsent.set(value) }
                    Text(String(localized: "只有同意后才会发送位置、时间、天气、输入条件和评价以生成推荐。可随时关闭；关闭后仍可查看演示内容。"))
                        .font(.footnote)
                    if let message { Text(message).foregroundStyle(.secondary) }
                    Link("隐私政策", destination: URL(string: "https://wliao78.github.io/My-Journey-Support/#privacy-" + (PublicLanguage.isChinese ? "zh" : "en"))!)
                    Link(String(localized: "使用支持"), destination: URL(string: "https://wliao78.github.io/My-Journey-Support/#support")!)
                    Link(String(localized: "联系开发者"), destination: URL(string: "mailto:tinyworm@gmail.com")!)
                    }
                    .padding(18)
                    .foodPanel()
                }
                .padding(18)
            }.defaultScrollAnchor(PublicLanguage.qaScrollBottom ? .bottom : .top)
            .background { FoodTheme.background }
            .foregroundStyle(.white)
            .tint(FoodTheme.accent)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "完成")) { dismiss() } } }
        }
    }
}
