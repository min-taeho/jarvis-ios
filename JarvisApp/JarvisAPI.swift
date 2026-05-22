import Foundation

actor JarvisAPI {
    static let shared = JarvisAPI()

    private let baseURL = URL(string: "http://devon.gonetis.com:8767")!

    private struct ChatRequest: Encodable {
        let text: String
        let session_id: String
    }

    struct ChatResponse: Decodable {
        let text: String
        let audio_base64: String
    }

    func chat(text: String, sessionId: String) async throws -> ChatResponse {
        let url = baseURL.appendingPathComponent("api/chat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ChatRequest(text: text, session_id: sessionId))
        req.timeoutInterval = 120
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }

    func clearSession(sessionId: String) async throws {
        let url = baseURL.appendingPathComponent("api/clear")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["session_id": sessionId])
        let _ = try await URLSession.shared.data(for: req)
    }

    func healthCheck() async -> Bool {
        let url = baseURL.appendingPathComponent("api/health")
        guard let (_, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}
