import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("publicAIProvider") private var providerID = PublicAIProvider.openAI.rawValue
    @State private var keyInput = ""
    @State private var hasSavedKey = APIKeyStore().load() != nil
    @State private var isTesting = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("设置")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("智能推荐服务")
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundStyle(FoodTheme.accent)
                    VStack(alignment: .leading, spacing: 14) {
                    Picker("AI 服务商", selection: $providerID) {
                        ForEach(PublicAIProvider.allCases) { provider in
                            Text(provider.title).tag(provider.rawValue)
                        }
                    }
                    .onChange(of: providerID) { _, _ in
                        hasSavedKey = APIKeyStore().load() != nil
                        keyInput = ""
                        message = nil
                    }
                    Label(hasSavedKey ? "密钥已保存" : "添加 API 密钥", systemImage: "key.fill")
                        .font(.headline)
                    SecureField("输入 API Key", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .padding(12)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    Button("保存密钥") {
                        if APIKeyStore().save(keyInput) {
                            keyInput = ""
                            hasSavedKey = true
                            message = "密钥已保存在本机钥匙串。"
                        } else { message = "保存失败，请重试。" }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(isTesting ? "正在测试…" : "测试连接") {
                        Task {
                            isTesting = true
                            defer { isTesting = false }
                            do {
                                try await AIModelRouter().testConnection()
                                message = "所选服务商连接成功。"
                            } catch { message = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasSavedKey || isTesting)
                    Button("清除密钥", role: .destructive) {
                        if APIKeyStore().clear() {
                            hasSavedKey = false
                            keyInput = ""
                            message = "密钥已从本机删除。"
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasSavedKey)
                    }
                    .padding(18)
                    .foodPanel()
                    VStack(alignment: .leading, spacing: 10) {
                    Label("隐私说明", systemImage: "hand.raised.fill")
                        .font(.headline)
                    Text("密钥只保存在这台设备的钥匙串。推荐时，位置、时间、天气、输入条件和评价会发送给所选 AI 服务商。")
                        .font(.footnote)
                    if let message { Text(message).foregroundStyle(.secondary) }
                    }
                    .padding(18)
                    .foodPanel()
                }
                .padding(18)
            }
            .background { FoodTheme.background }
            .foregroundStyle(.white)
            .tint(FoodTheme.accent)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
