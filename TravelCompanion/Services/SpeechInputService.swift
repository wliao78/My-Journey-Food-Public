import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechInputService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var startGeneration = 0

    func toggle() async {
        if isListening {
            stop()
        } else {
            await start()
        }
    }

    func start() async {
        startGeneration += 1
        let generation = startGeneration
        guard recognizer?.isAvailable == true else {
            errorMessage = "当前设备暂不支持语音识别。"
            return
        }
        let speechAllowed = await Self.requestSpeechAuthorization()
        guard generation == startGeneration else { return }
        guard speechAllowed else {
            errorMessage = "请在系统设置中允许语音识别。"
            return
        }

        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        guard generation == startGeneration else { return }
        guard microphoneAllowed else {
            errorMessage = "请在系统设置中允许使用麦克风。"
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        transcript = ""
        errorMessage = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            Self.installAudioTap(on: inputNode, format: format, request: request)
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            errorMessage = "语音输入未能启动：\(error.localizedDescription)"
            stop()
            return
        }

        if let recognizer {
            recognitionTask = Self.makeRecognitionTask(recognizer: recognizer, request: request, owner: self)
        }
    }

    func stop() {
        startGeneration += 1
        guard isListening || recognitionRequest != nil else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private nonisolated static func installAudioTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
    }

    private nonisolated static func makeRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        owner: SpeechInputService
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor [weak owner] in
                guard owner?.isListening == true else { return }
                if let text { owner?.transcript = text }
                if failed || isFinal { owner?.stop() }
            }
        }
    }
}
