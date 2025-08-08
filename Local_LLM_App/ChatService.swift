import Foundation

struct ChatCompletionRequest: Codable {
    let message: String
    let messages: [Message]? // 履歴
    let provider: String?    // サーバー側のプロバイダ切り替え用（例: ollama|gemini）
}

struct ChatCompletionResponse: Codable {
    let reply: String
}

enum ChatProvider: String, CaseIterable {
    case ollama

    var displayName: String { "Ollama" }
}

struct Message: Codable {
    let role: String // user|assistant|system
    let content: String
}

final class ChatService {
    private let baseURL: URL
    private let urlSession: URLSession
    private let provider: ChatProvider

    init(baseURL: URL, provider: ChatProvider = .ollama, urlSession: URLSession? = nil) {
        self.baseURL = baseURL
        self.provider = provider

        if let urlSession {
            self.urlSession = urlSession
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 600
            config.timeoutIntervalForResource = 600
            config.waitsForConnectivity = true
            self.urlSession = URLSession(configuration: config)
        }
    }

    private func endpointURL(path: String) throws -> URL {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "ChatService", code: -2, userInfo: [NSLocalizedDescriptionKey: "無効なURL"])
        }
        comps.path = path
        comps.query = nil
        comps.fragment = nil
        guard let url = comps.url else {
            throw NSError(domain: "ChatService", code: -3, userInfo: [NSLocalizedDescriptionKey: "URL生成に失敗"])
        }
        return url
    }

    func sendMessage(_ text: String, history: [Message] = []) async throws -> String {
        let endpoint = try endpointURL(path: "/chat")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ChatCompletionRequest(message: text, messages: history.isEmpty ? nil : history, provider: provider.rawValue)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let status = http.statusCode
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "ChatService", code: status, userInfo: [NSLocalizedDescriptionKey: "HTTPステータス異常: \(status)\n\(bodyText)"])
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return decoded.reply
    }

    func sendMessageStreaming(
        _ text: String,
        history: [Message] = [],
        onToken: @escaping (String) -> Void,
        onUsage: @escaping (_ prompt: Int?, _ completion: Int?, _ total: Int?) -> Void = { _,_,_ in }
    ) async throws {
        let path = "/chat_stream"
        let endpoint = try endpointURL(path: path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // サーバは NDJSON を返すため Accept を明示
        request.setValue("application/x-ndjson, application/json", forHTTPHeaderField: "Accept")
        let body = ChatCompletionRequest(message: text, messages: history.isEmpty ? nil : history, provider: provider.rawValue)
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await urlSession.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "ChatService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTPステータス異常: \(http.statusCode)"])
        }

        // サーバは application/x-ndjson を返す（1行1JSON）。SSE("data: ")にも後方互換で対応。
        for try await rawLine in bytes.lines {
            if rawLine.isEmpty { continue }

            if rawLine.hasPrefix("data: ") {
                // SSE 形式: "data: ..."
                let content = String(rawLine.dropFirst(6))
                if content == "[DONE]" { break }
                if content.hasPrefix("[USAGE]") {
                    if let jsonStart = content.range(of: "{"), let data = content[jsonStart.lowerBound...].data(using: .utf8) {
                        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let p = obj["prompt"] as? Int
                            let c = obj["completion"] as? Int
                            let t = obj["total"] as? Int
                            onUsage(p, c, t)
                        }
                    }
                    continue
                }
                // 可能なら JSON として解釈（{"response": "..."} 仮定）
                if let data = content.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let resp = obj["response"] as? String { onToken(resp); continue }
                    if let err = obj["error"] as? String { throw NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: err]) }
                }
                onToken(content)
                continue
            }

            // NDJSON or plain text
            if let data = rawLine.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let resp = obj["response"] as? String {
                    onToken(resp)
                    continue
                }
                if let err = obj["error"] as? String {
                    throw NSError(domain: "ChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
                }
            }

            // JSONでなければそのままテキストとして扱う
            onToken(rawLine)
        }
    }

    func checkHealth() async throws -> (status: String, model: String) {
        let endpoint = try endpointURL(path: "/healthz")
        let (data, response) = try await urlSession.data(from: endpoint)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let status = http.statusCode
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "ChatService", code: status, userInfo: [NSLocalizedDescriptionKey: "ヘルスチェック失敗: \(status)\n\(bodyText)"])
        }
        struct Health: Decodable { let status: String; let model: String }
        let h = try JSONDecoder().decode(Health.self, from: data)
        return (h.status, h.model)
    }
}

