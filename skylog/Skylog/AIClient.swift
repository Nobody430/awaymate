import Foundation

/// Minimal AI client (raw HTTP): Claude (Anthropic) or OpenAI, selectable in the settings.
enum AIClient {
    enum Provider: String, CaseIterable, Identifiable {
        case claudeFast, claudeBest, openai
        var id: String { rawValue }
        var label: String {
            switch self {
            case .claudeFast: "Claude Haiku – günstig (empfohlen)"
            case .claudeBest: "Claude Opus – am genausten"
            case .openai: "OpenAI (eigenes API-Guthaben)"
            }
        }
    }

    static var provider: Provider {
        Provider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "") ?? .claudeFast
    }

    private static func setting(_ key: String) -> String {
        (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var hasKey: Bool {
        provider == .openai ? !setting("openaiKey").isEmpty : !setting("anthropicKey").isEmpty
    }

    struct Failure: LocalizedError {
        let message: String
        /// Worth trying again shortly (overload, rate limit)
        var retryable = false
        var retryAfter: Double? = nil
        /// Will fail again for every request (bad key, no credit)
        var fatal = false
        var errorDescription: String? { message }
    }

    /// Sends one request and returns the text output. With `schema`, the output is constrained to that JSON schema.
    static func send(system: String, user: String, schema: [String: Any]? = nil,
                     effort: String = "medium", maxTokens: Int = 16000) async throws -> String {
        guard hasKey else { throw Failure(message: "Kein KI-Key hinterlegt (Einstellungen → KI-Erkennung).") }
        return provider == .openai
            ? try await openAI(system: system, user: user, schema: schema)
            : try await claude(system: system, user: user, schema: schema, effort: effort, maxTokens: maxTokens)
    }

    // MARK: Claude

    private static func claude(system: String, user: String, schema: [String: Any]?, effort: String, maxTokens: Int) async throws -> String {
        let model = provider == .claudeBest ? "claude-opus-5-5" : "claude-haiku-5-5"
        var outputConfig: [String: Any] = ["effort": effort]
        if let schema { outputConfig["format"] = ["type": "json_schema", "schema": schema] }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "output_config": outputConfig,
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        if provider == .claudeBest {
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(setting("anthropicKey"), forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let json = try await perform(request)
        switch json["stop_reason"] as? String {
        case "refusal": throw Failure(message: "Die Anfrage wurde abgelehnt.")
        case "max_tokens": throw Failure(message: "Antwort zu lang – bitte nochmal versuchen.")
        default: break
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw Failure(message: "Leere Antwort erhalten.") }
        return text
    }

    // MARK: OpenAI

    private static func openAI(system: String, user: String, schema: [String: Any]?) async throws -> String {
        let model = setting("openaiModel").isEmpty ? "gpt-5-mini" : setting("openaiModel")
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        if let schema {
            body["response_format"] = ["type": "json_schema", "json_schema": ["name": "result", "strict": true, "schema": schema]]
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(setting("openaiKey"))", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let json = try await perform(request)
        let choice = (json["choices"] as? [[String: Any]])?.first
        let message = choice?["message"] as? [String: Any]
        if let refusal = message?["refusal"] as? String, !refusal.isEmpty { throw Failure(message: "Die Anfrage wurde abgelehnt.") }
        switch choice?["finish_reason"] as? String {
        case "length": throw Failure(message: "Antwort zu lang – bitte nochmal versuchen.")
        case "content_filter": throw Failure(message: "Die Anfrage wurde abgelehnt.")
        default: break
        }
        guard let text = message?["content"] as? String, !text.isEmpty else {
            throw Failure(message: "Leere Antwort erhalten.")
        }
        return text
    }

    // MARK: Shared

    /// Sends the request; retries overload, rate limits and network hiccups up to 3 times with a pause.
    private static func perform(_ request: URLRequest) async throws -> [String: Any] {
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await performOnce(request)
            } catch let f as Failure where f.retryable && attempt < 4 {
                try await Task.sleep(for: .seconds(f.retryAfter ?? Double(attempt * attempt * 3)))
            } catch let e as URLError where attempt < 3 && [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost].contains(e.code) {
                try await Task.sleep(for: .seconds(Double(attempt * 4)))
            }
        }
    }

    private static func performOnce(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if (500...599).contains(status) || status == 429 { throw Failure(message: "KI-Dienst überlastet – bitte später nochmal.", retryable: true) }
            throw Failure(message: "Unlesbare Antwort vom KI-Dienst (HTTP \(status)): " + String(decoding: data.prefix(200), as: UTF8.self))
        }
        guard status == 200 else {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            let wait = http?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init).map { min($0, 60) }
            switch status {
            case 401: throw Failure(message: "API-Key ungültig.", fatal: true)
            case 402: throw Failure(message: "Kein Guthaben mehr auf dem KI-Konto.", fatal: true)
            case 429 where msg.lowercased().contains("quota") || msg.lowercased().contains("credit") || msg.lowercased().contains("billing"):
                throw Failure(message: "Kein Guthaben mehr auf dem KI-Konto. (\(msg))", fatal: true)
            case 429: throw Failure(message: "Zu viele Anfragen – kurz warten. (\(msg))", retryable: true, retryAfter: wait)
            case 408, 529, 500...599: throw Failure(message: "KI-Dienst überlastet – bitte später nochmal.", retryable: true, retryAfter: wait)
            default: throw Failure(message: msg)
            }
        }
        return json
    }
}
