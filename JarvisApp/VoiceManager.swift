import AVFoundation
import Speech

// Helper: keeps AVAudioPlayerDelegate off the main actor
private final class AudioPlayerHelper: NSObject, AVAudioPlayerDelegate {
    var onFinish: () -> Void = {}
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        onFinish()
    }
}

@MainActor
final class VoiceManager: NSObject, ObservableObject {

    enum AppState: Equatable { case idle, listening, processing, speaking }

    @Published var appState: AppState = .idle
    @Published var liveTranscript = ""
    @Published var lastResponse = ""
    @Published var errorMessage: String?
    @Published var isConnected = false

    let sessionId = UUID().uuidString

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayer?
    private let playerHelper = AudioPlayerHelper()

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
        guard appState == .idle else { return }
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
                        if code != 301 && code != 203 { // 301=cancelled, 203=no speech
                            self.stopEngine()
                            if self.appState == .listening { self.appState = .idle }
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

    private func finishAndSend() {
        stopEngine()
        let text = liveTranscript.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { appState = .idle; return }
        appState = .processing
        Task { await sendText(text) }
    }

    private func stopEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    // MARK: - API + Playback

    private func sendText(_ text: String) async {
        do {
            let response = try await JarvisAPI.shared.chat(text: text, sessionId: sessionId)
            lastResponse = response.text
            if let audioData = Data(base64Encoded: response.audio_base64) {
                await playAudio(data: audioData)
            }
        } catch {
            errorMessage = "오류: \(error.localizedDescription)"
        }
        appState = .idle
    }

    private func playAudio(data: Data) async {
        appState = .speaking
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            do {
                audioPlayer = try AVAudioPlayer(data: data)
                playerHelper.onFinish = { cont.resume() }
                audioPlayer?.delegate = playerHelper
                audioPlayer?.play()
            } catch {
                cont.resume()
            }
        }
    }

    // MARK: - Session

    func clearSession() {
        lastResponse = ""
        liveTranscript = ""
        Task { try? await JarvisAPI.shared.clearSession(sessionId: sessionId) }
    }
}
