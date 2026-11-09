import Foundation

/// Minimal AI client (raw HTTP): Claude (Anthropic) or OpenAI, selectable in the settings.
enum AIClient {
    enum Provider: String, CaseIterable, Identifiable {
        case claudeFast, claudeBest, openai
        var id: String { rawValue }
        var label: String {
            switch self {
            case .claudeFast: "Claude Haiku – günstig"
            case .claudeBest: "Claude Opus – am genausten (empfohlen)"
            case .openai: "OpenAI (eigenes API-Guthaben)"
            }
        }
    }

    static var provider: Provider {
        Provider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "") ?? .claudeBest
    }

    private static func setting(_ key: String) -> String {
        (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var hasKey: Bool {
        provider == .openai ? !setting("openaiKey").isEmpty : !setting("anthropicKey").isEmpty
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Sends one request and returns the text output. With `schema`, the output is constrained to that JSON schema.
    static func send(system: String, user: String, schema: [String: Any]? = nil,
                     effort: String = "medium", maxTokens: Int = 16000) async throws -> String {
        guard hasKey else { throw Failure(message: "Kein KI-Key hinterlegt (Einstellungen → KI-Coach).") }
        return provider == .openai
            ? try await openAI(system: system, user: user, schema: schema)
            : try await claude(system: system, user: user, schema: schema, effort: effort, maxTokens: maxTokens)
    }

    /// Sends a JPEG image plus text (vision).
    static func send(system: String, imageJPEG: Data, text: String, schema: [String: Any]? = nil,
                     effort: String = "medium", maxTokens: Int = 8000) async throws -> String {
        guard hasKey else { throw Failure(message: "Kein KI-Key hinterlegt (Einstellungen → KI-Coach).") }
        let b64 = imageJPEG.base64EncodedString()
        if provider == .openai {
            let content: [[String: Any]] = [
                ["type": "text", "text": text],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]],
            ]
            return try await openAI(system: system, user: content, schema: schema)
        }
        let content: [[String: Any]] = [
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]],
            ["type": "text", "text": text],
        ]
        return try await claude(system: system, user: content, schema: schema, effort: effort, maxTokens: maxTokens)
    }

    // MARK: Claude

    private static func claude(system: String, user: Any, schema: [String: Any]?, effort: String, maxTokens: Int) async throws -> String {
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

    private static func openAI(system: String, user: Any, schema: [String: Any]?) async throws -> String {
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
        guard let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any],
              let text = message["content"] as? String, !text.isEmpty else {
            throw Failure(message: "Leere Antwort erhalten.")
        }
        return text
    }

    // MARK: Shared

    private static func perform(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            switch status {
            case 401: throw Failure(message: "API-Key ungültig.")
            case 402: throw Failure(message: "Kein Guthaben mehr auf dem KI-Konto.")
            case 429: throw Failure(message: "Zu viele Anfragen oder kein Guthaben – kurz warten bzw. Guthaben prüfen. (\(msg))")
            case 529, 500...599: throw Failure(message: "KI-Dienst überlastet – bitte später nochmal.")
            default: throw Failure(message: msg)
            }
        }
        return json
    }

    static func translate(_ lines: [String]) async throws -> [String] {
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["steps"],
            "properties": ["steps": ["type": "array", "items": ["type": "string"]]],
        ]
        let text = try await send(
            system: "Du übersetzt Trainingsanleitungen präzise und natürlich ins Deutsche (Schweizer Rechtschreibung, kein ß). Behalte die Anzahl und Reihenfolge der Schritte bei.",
            user: lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"),
            schema: schema, effort: "low", maxTokens: 4000)
        struct Out: Decodable { let steps: [String] }
        return try JSONDecoder().decode(Out.self, from: Data(text.utf8)).steps
    }
}
