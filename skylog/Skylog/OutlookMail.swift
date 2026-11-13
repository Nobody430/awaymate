import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit

enum MailError: LocalizedError {
    case noClientID, cancelled, auth(String), http(Int)

    var errorDescription: String? {
        switch self {
        case .noClientID: String(localized: "Keine Outlook-Client-ID hinterlegt (Einstellungen).")
        case .cancelled: String(localized: "Anmeldung abgebrochen.")
        case .auth(let msg): String(localized: "Anmeldung fehlgeschlagen: \(msg)")
        case .http(let code) where (500...599).contains(code): String(localized: "Outlook antwortet gerade nicht (Fehler \(code)). Die App versucht es später wieder.")
        case .http(let code): String(localized: "Outlook-Fehler (\(code)). Evtl. neu verbinden.")
        }
    }
}

enum Keychain {
    private static let service = "com.nobody430.skylog"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Microsoft account login (Outlook.com / Hotmail / MSN / Microsoft 365) via OAuth 2.0 + PKCE.
final class OutlookAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OutlookAuth()
    static let callbackScheme = "msauth.com.nobody430.skylog"
    static let redirectURI = "msauth.com.nobody430.skylog://auth"
    /// "consumers" works for personal Outlook/Hotmail/MSN accounts with both personal-only and mixed app registrations.
    private static let authority = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
    private static let scope = "offline_access User.Read Mail.Read"
    private static let refreshKey = "outlookRefreshToken"

    private var accessToken: String?
    private var expiry: Date = .distantPast
    private var session: ASWebAuthenticationSession?

    var clientID: String {
        (UserDefaults.standard.string(forKey: "outlookClientID") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var isConnected: Bool { Keychain.get(Self.refreshKey) != nil }

    func signOut() {
        Keychain.set(nil, for: Self.refreshKey)
        accessToken = nil
        expiry = .distantPast
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    @MainActor
    func signIn() async throws {
        guard !clientID.isEmpty else { throw MailError.noClientID }
        let verifier = Self.randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL

        var comps = URLComponents(string: Self.authority + "/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: Self.callbackScheme) { url, error in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: MailError.cancelled) }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error_description" })?.value ?? items.first(where: { $0.name == "error" })?.value {
            throw MailError.auth(err.replacingOccurrences(of: "+", with: " "))
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw MailError.auth(String(localized: "kein Code")) }
        try await token([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
            "scope": Self.scope,
        ])
    }

    func validToken() async throws -> String {
        if let accessToken, expiry > Date().addingTimeInterval(60) { return accessToken }
        guard let refresh = Keychain.get(Self.refreshKey) else { throw MailError.auth(String(localized: "nicht verbunden")) }
        try await token([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "scope": Self.scope,
        ])
        guard let accessToken else { throw MailError.auth(String(localized: "kein Token")) }
        return accessToken
    }

    private struct TokenResponse: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Double?
        let error_description: String?
        let error: String?
    }

    private func token(_ form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: Self.authority + "/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let access = response.access_token else {
            // Only a really invalid login signs out – not a temporary server problem
            if form["grant_type"] == "refresh_token", ["invalid_grant", "interaction_required"].contains(response.error ?? "") { signOut() }
            throw MailError.auth(response.error_description ?? String(localized: "unbekannt"))
        }
        accessToken = access
        expiry = Date().addingTimeInterval(response.expires_in ?? 3600)
        if let r = response.refresh_token { Keychain.set(r, for: Self.refreshKey) }
    }

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Searches the mailbox via Microsoft Graph for flight-related mails.
enum OutlookMail {
    static let queries = ["flight", "flug", "boarding", "boarding pass", "bordkarte", "booking confirmation",
                          "buchungsbestätigung", "buchungsbestaetigung", "itinerary", "reiseplan", "e-ticket", "eticket",
                          "check-in", "online check-in", "reservation", "reservierung", "booking.com", "flugbuchung",
                          "flight booking", "deine reise", "your trip", "ihre reise", "votre vol", "su vuelo",
                          "swiss", "lufthansa", "easyjet", "edelweiss", "ryanair", "eurowings", "iberia", "aerolineas",
                          "delta", "emirates", "qatar", "turkish", "klm", "air france", "british airways", "tap",
                          "skyscanner", "edreams", "opodo", "expedia", "lastminute", "kiwi.com"]

    private struct Page: Decodable {
        let value: [Message]
        let nextLink: String?
        enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
        }
    }

    private struct Message: Decodable {
        let id: String
        let subject: String?
        let receivedDateTime: String?
        let body: Body?
        let from: From?
        struct Body: Decodable { let content: String? }
        struct From: Decodable {
            let emailAddress: Address?
            struct Address: Decodable { let name: String?; let address: String? }
        }
    }

    struct MailItem: Hashable {
        let id: String
        let subject: String
        let from: String
        let received: Date
        let text: String
    }

    /// Mails received since a date (for the periodic background check).
    static func recentMails(since: Date) async throws -> [MailItem] {
        let token = try await OutlookAuth.shared.validToken()
        let iso = ISO8601DateFormatter()
        var comps = URLComponents(string: "https://graph.microsoft.com/v1.0/me/messages")!
        comps.queryItems = [
            URLQueryItem(name: "$filter", value: "receivedDateTime ge \(iso.string(from: since))"),
            URLQueryItem(name: "$orderby", value: "receivedDateTime desc"),
            URLQueryItem(name: "$select", value: "subject,receivedDateTime,body,from"),
            // small pages: Outlook answers 502/504 when a page with full mail texts gets too large
            URLQueryItem(name: "$top", value: "15"),
        ]
        var next: URL? = comps.url
        var mails: [MailItem] = []
        var pages = 0
        while let url = next, pages < 20 {
            var request = URLRequest(url: url)
            request.timeoutInterval = 45
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("outlook.body-content-type=\"text\"", forHTTPHeaderField: "Prefer")
            var (data, response) = try await URLSession.shared.data(for: request)
            if let code = (response as? HTTPURLResponse)?.statusCode, (500...599).contains(code) {
                // gateway hiccup: one more try after a short pause
                try await Task.sleep(for: .seconds(3))
                (data, response) = try await URLSession.shared.data(for: request)
            }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MailError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
            let page = try JSONDecoder().decode(Page.self, from: data)
            for msg in page.value {
                mails.append(MailItem(
                    id: msg.id, subject: msg.subject ?? "",
                    from: msg.from?.emailAddress?.address ?? msg.from?.emailAddress?.name ?? "",
                    received: msg.receivedDateTime.flatMap { iso.date(from: $0) } ?? Date(),
                    text: DocumentText.stripHTML(msg.body?.content ?? "")))
            }
            next = page.nextLink.flatMap(URL.init(string:))
            pages += 1
        }
        return mails
    }

    /// Fetches all mails matching the travel queries (deduplicated), newest first.
    static func fetchMails(progress: @escaping @MainActor (String) -> Void) async throws -> [MailItem] {
        let token = try await OutlookAuth.shared.validToken()
        var seen = Set<String>()
        var mails: [MailItem] = []
        let iso = ISO8601DateFormatter()
        for query in queries {
            await progress(String(localized: "Suche „\(query)“ … (\(seen.count) Mails)"))
            var comps = URLComponents(string: "https://graph.microsoft.com/v1.0/me/messages")!
            comps.queryItems = [
                URLQueryItem(name: "$search", value: "\"\(query)\""),
                URLQueryItem(name: "$select", value: "subject,receivedDateTime,body,from"),
                URLQueryItem(name: "$top", value: "50"),
            ]
            var next: URL? = comps.url
            var pages = 0
            while let url = next, pages < 30 {
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("outlook.body-content-type=\"text\"", forHTTPHeaderField: "Prefer")
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else { throw MailError.http(code) }
                let page = try JSONDecoder().decode(Page.self, from: data)
                for msg in page.value where !seen.contains(msg.id) {
                    seen.insert(msg.id)
                    mails.append(MailItem(
                        id: msg.id, subject: msg.subject ?? "",
                        from: msg.from?.emailAddress?.address ?? msg.from?.emailAddress?.name ?? "",
                        received: msg.receivedDateTime.flatMap { iso.date(from: $0) } ?? Date(),
                        text: DocumentText.stripHTML(msg.body?.content ?? "")))
                }
                next = page.nextLink.flatMap(URL.init(string:))
                pages += 1
            }
        }
        return mails.sorted { $0.received > $1.received }
    }

    static func scan(progress: @escaping @MainActor (String) -> Void) async throws -> [FlightCandidate] {
        let token = try await OutlookAuth.shared.validToken()
        var seen = Set<String>()
        var result: [String: FlightCandidate] = [:]
        let iso = ISO8601DateFormatter()

        for query in queries {
            await progress(String(localized: "Suche „\(query)“ … (\(seen.count) Mails geprüft)"))
            var comps = URLComponents(string: "https://graph.microsoft.com/v1.0/me/messages")!
            comps.queryItems = [
                URLQueryItem(name: "$search", value: "\"\(query)\""),
                URLQueryItem(name: "$select", value: "subject,receivedDateTime,body"),
                URLQueryItem(name: "$top", value: "50"),
            ]
            var next: URL? = comps.url
            var pages = 0
            while let url = next, pages < 30 {
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("outlook.body-content-type=\"text\"", forHTTPHeaderField: "Prefer")
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else { throw MailError.http(code) }
                let page = try JSONDecoder().decode(Page.self, from: data)
                for msg in page.value where !seen.contains(msg.id) {
                    seen.insert(msg.id)
                    let text = (msg.subject ?? "") + "\n" + DocumentText.stripHTML(msg.body?.content ?? "")
                    let ref = msg.receivedDateTime.flatMap { iso.date(from: $0) } ?? Date()
                    for c in FlightTextParser.parse(text, source: msg.subject ?? String(localized: "E-Mail"), reference: ref)
                    where result[c.id] == nil {
                        result[c.id] = c
                    }
                }
                next = page.nextLink.flatMap(URL.init(string:))
                pages += 1
            }
        }
        await progress(String(localized: "\(seen.count) Mails geprüft, \(result.count) Flüge gefunden."))
        return result.values.sorted { $0.date > $1.date }
    }
}
