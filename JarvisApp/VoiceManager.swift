import AVFoundation
import Combine
import Speech

private final class AudioPlayerHelper: NSObject, AVAudioPlayerDelegate {
    var onFinish: () -> Void = {}
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        onFinish()
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    enum Role { case user, assistant }
}

@MainActor
final class VoiceManager: NSObject, ObservableObject {

    enum AppState: Equatable { case idle, listening, processing, speaking }

    @Published var appState: AppState = .idle
    @Published var liveTranscript = ""
    @Published var messages: [ChatMessage] = []
    @Published var errorMessage: String?
    @Published var isConnected = false
    @Published var queueCount = 0

    let sessionId = UUID().uuidString

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayer?
    private let playerHelper = AudioPlayerHelper()

    private var requestQueue: [String] = []
    private var isApiProcessing = false
    private var audioPlayContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micOK = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return speechOK && micOK
    }

    func checkConnection() async {
        isConnected = await JarvisAPI.shared.healthCheck()
    }

    // MARK: - Listening

    func startListening() {
        if appState == .speaking { interruptAudio() }
        guard appState == .idle || appState == .processing else { return }

        liveTranscript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            recognitionRequest?.shouldReportPartialResults = true

            guard let req = recognitionRequest,
                  let recognizer = speechRecognizer, recognizer.isAvailable else {
                errorMessage = "음성 인식을 사용할 수 없습니다."
                return
            }

            recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.liveTranscript = result.bestTranscription.formattedString
                        if result.isFinal { self.finishAndSend() }
                    }
                    if let error {
                        let code = (error as NSError).code
                        if code != 301 && code != 203 {
                            self.stopEngine()
                            if self.appState == .listening {
                                self.appState = self.isApiProcessing ? .processing : .idle
                            }
                        }
                    }
                }
            }

            let inputNode = audioEngine.inputNode
            let fmt = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
                self?.recognitionRequest?.append(buf)
            }

            audioEngine.prepare()
            try audioEngine.start()
            appState = .listening

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopListening() {
        guard appState == .listening else { return }
        finishAndSend()
    }

    private func interruptAudio() {
        guard let cont = audioPlayContinuation else { return }
        audioPlayContinuation = nil
        playerHelper.onFinish = {}
        audioPlayer?.stop()
        cont.resume()
    }

    private func finishAndSend() {
        stopEngine()
        let text = liveTranscript.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            appState = isApiProcessing ? .processing : .idle
            return
        }
        messages.append(ChatMessage(role: .user, text: text))
        requestQueue.append(text)
        queueCount = requestQueue.count
        appState = .processing
        if !isApiProcessing { processQueue() }
    }

    private func stopEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    // MARK: - Queue

    private func processQueue() {
        guard !requestQueue.isEmpty else {
            isApiProcessing = false
            if appState != .listening { appState = .idle }
            return
        }
        isApiProcessing = true
        let text = requestQueue.removeFirst()
        queueCount = requestQueue.count
        Task { await sendText(text) }
    }

    // MARK: - API + Playback

    private func sendText(_ text: String) async {
        do {
            let response = try await JarvisAPI.shared.chat(text: text, sessionId: sessionId)
            messages.append(ChatMessage(role: .assistant, text: response.text))
            if let audioData = Data(base64Encoded: response.audio_base64) {
                await playAudio(data: audioData)
            }
        } catch {
            errorMessage = "오류: \(error.localizedDescription)"
        }
        processQueue()
    }

    private func playAudio(data: Data) async {
        guard appState != .listening else { return }
        appState = .speaking
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            do {
                audioPlayer = try AVAudioPlayer(data: data)
                playerHelper.onFinish = { [weak self] in
                    self?.audioPlayContinuation = nil
                    cont.resume()
                }
                audioPlayContinuation = cont
                audioPlayer?.delegate = playerHelper
                audioPlayer?.play()
            } catch {
                audioPlayContinuation = nil
                cont.resume()
            }
        }

        if appState == .speaking {
            appState = isApiProcessing ? .processing : .idle
        }
    }

    // MARK: - Session

    func clearSession() {
        messages = []
        liveTranscript = ""
        requestQueue = []
        queueCount = 0
        isApiProcessing = false
        Task { try? await JarvisAPI.shared.clearSession(sessionId: sessionId) }
    }
}
