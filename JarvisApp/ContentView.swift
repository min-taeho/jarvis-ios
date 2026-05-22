import SwiftUI

struct ContentView: View {
    @StateObject private var voice = VoiceManager()
    @State private var hasPermission = false
    @State private var showClearConfirm = false

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                conversationView
                controlsView
            }
        }
        .task {
            hasPermission = await voice.requestPermissions()
            await voice.checkConnection()
        }
        .confirmationDialog("대화 초기화", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("초기화", role: .destructive) { voice.clearSession() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("현재 대화 기록을 서버에서 삭제합니다.")
        }
        .alert("오류", isPresented: .init(
            get: { voice.errorMessage != nil },
            set: { if !$0 { voice.errorMessage = nil } }
        )) {
            Button("확인") { voice.errorMessage = nil }
        } message: {
            Text(voice.errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("JARVIS")
                    .font(.system(size: 20, weight: .thin, design: .monospaced))
                    .foregroundColor(.cyan)
                    .tracking(6)
                HStack(spacing: 4) {
                    Circle()
                        .fill(voice.isConnected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(voice.isConnected ? "연결됨" : "연결 안 됨")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            Spacer()
            Button(action: { showClearConfirm = true }) {
                Image(systemName: "trash")
                    .foregroundColor(.gray)
                    .font(.system(size: 15))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Conversation

    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    if voice.lastResponse.isEmpty && voice.liveTranscript.isEmpty {
                        placeholderView
                    }
                    if !voice.lastResponse.isEmpty {
                        ResponseBubble(text: voice.lastResponse).id("response")
                    }
                    if !voice.liveTranscript.isEmpty {
                        TranscriptBubble(text: voice.liveTranscript).id("transcript")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: voice.liveTranscript) { _ in
                withAnimation { proxy.scrollTo("transcript", anchor: .bottom) }
            }
            .onChange(of: voice.lastResponse) { _ in
                withAnimation { proxy.scrollTo("response", anchor: .bottom) }
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 60)
            Image(systemName: "waveform")
                .font(.system(size: 52))
                .foregroundColor(.cyan.opacity(0.25))
            Text("아래 버튼을 눌러 자비스와 대화하세요")
                .font(.system(size: 15))
                .foregroundColor(Color.gray.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    // MARK: - Controls

    private var controlsView: some View {
        VStack(spacing: 14) {
            Text(statusText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(statusColor.opacity(0.9))
                .animation(.easeInOut, value: voice.appState)

            ZStack {
                // Pulse ring (listening only)
                if voice.appState == .listening {
                    Circle()
                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                        .frame(width: 110, height: 110)
                        .scaleEffect(1.15)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: voice.appState)
                }

                Button(action: handleTap) {
                    ZStack {
                        Circle()
                            .fill(buttonColor.opacity(0.12))
                            .frame(width: 88, height: 88)
                        Circle()
                            .strokeBorder(buttonColor, lineWidth: 1.5)
                            .frame(width: 88, height: 88)
                        Image(systemName: buttonIcon)
                            .font(.system(size: 34, weight: .light))
                            .foregroundColor(buttonColor)
                    }
                }
                .disabled(!hasPermission || voice.appState == .processing || voice.appState == .speaking)
            }
        }
        .padding(.bottom, 52)
        .padding(.top, 16)
    }

    // MARK: - Actions

    private func handleTap() {
        switch voice.appState {
        case .idle: voice.startListening()
        case .listening: voice.stopListening()
        default: break
        }
    }

    // MARK: - Computed

    private var statusText: String {
        switch voice.appState {
        case .idle:       return hasPermission ? "탭하여 말하기" : "마이크 권한이 필요합니다"
        case .listening:  return "듣는 중 — 다시 탭하면 전송"
        case .processing: return "처리 중..."
        case .speaking:   return "응답 중..."
        }
    }

    private var statusColor: Color {
        switch voice.appState {
        case .idle:       return .gray
        case .listening:  return .red
        case .processing: return .orange
        case .speaking:   return .green
        }
    }

    private var buttonColor: Color {
        switch voice.appState {
        case .idle:       return .cyan
        case .listening:  return .red
        case .processing: return .orange
        case .speaking:   return .green
        }
    }

    private var buttonIcon: String {
        switch voice.appState {
        case .idle:       return "mic"
        case .listening:  return "stop.fill"
        case .processing: return "ellipsis"
        case .speaking:   return "speaker.wave.2"
        }
    }
}

// MARK: - Bubble Views

struct ResponseBubble: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "j.circle.fill")
                .foregroundColor(.cyan)
                .font(.system(size: 20))
            Text(text)
                .foregroundColor(.white)
                .font(.system(size: 16))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

struct TranscriptBubble: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(text)
                .foregroundColor(Color.cyan.opacity(0.75))
                .font(.system(size: 15))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "person.circle")
                .foregroundColor(Color.cyan.opacity(0.4))
                .font(.system(size: 20))
        }
        .padding(16)
        .background(Color.cyan.opacity(0.04))
        .cornerRadius(16)
    }
}
