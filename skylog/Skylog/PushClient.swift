import Foundation
import UIKit

/// Connection to the Skylog push server: registers the device and syncs upcoming flights.
@MainActor
enum PushClient {
    static var serverURL: String { (UserDefaults.standard.string(forKey: "pushServerURL") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    static var serverToken: String { (UserDefaults.standard.string(forKey: "pushServerToken") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    static var isConfigured: Bool { !serverURL.isEmpty && !serverToken.isEmpty }

    /// Language the app is shown in ("de", "en" …) – the server writes its notifications in it.
    static var appLanguage: String { String((Bundle.main.preferredLocalizations.first ?? "de").prefix(2)) }

    static var deviceToken: String? {
        get { UserDefaults.standard.string(forKey: "apnsDeviceToken") }
        set { UserDefaults.standard.set(newValue, forKey: "apnsDeviceToken") }
    }

    private static var liveTokens: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "liveActivityTokens") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "liveActivityTokens") }
    }

    static var lastStatus: String?

    static func register() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func didRegister(_ token: Data) {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        scheduleSync()
    }

    static func setLiveToken(flightID: String, token: Data) {
        var t = liveTokens
        t[flightID] = token.map { String(format: "%02x", $0) }.joined()
        liveTokens = t
        scheduleSync()
    }

    private static var pending: Task<Void, Never>?

    /// Debounced sync after changes.
    static func scheduleSync() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await sync()
        }
    }

    private static func endpoint(_ path: String) -> URL? {
        var base = serverURL
        if !base.hasPrefix("http") { base = "https://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)
    }

    private static func payload(for f: Flight) -> [String: Any]? {
        guard let dep = f.departure.best else { return nil }
        let iso = ISO8601DateFormatter()
        var p: [String: Any] = [
            "id": f.id.uuidString, "number": FlightStore.normalizedNumber(f.number),
            "from": f.departure.code, "to": f.arrival.code, "toCity": f.arrival.displayCity,
            "dep": iso.string(from: dep), "depTz": f.departure.tz.identifier, "arrTz": f.arrival.tz.identifier,
            "statusLabel": f.normalizedStatus.label, "longHaul": (f.computedDistanceKm ?? 0) > 3500,
        ]
        if let arr = f.arrival.best { p["arr"] = iso.string(from: arr) }
        if let cs = LiveADSB.callsign(for: f) { p["callsign"] = cs }
        if let g = f.departure.gate { p["gate"] = g }
        if let t = f.departure.terminal { p["terminal"] = t }
        if let c = f.arrival.coordinate { p["toLat"] = c.latitude; p["toLon"] = c.longitude }
        if let fa = f.faFlightID { p["faFlightID"] = fa }
        return p
    }

    static func sync() async {
        guard isConfigured, let token = deviceToken, let url = endpoint("/sync") else { return }
        let horizon = Date().addingTimeInterval(7 * 86400)
        let flights = FlightStore.shared.upcoming
            .filter { !$0.normalizedStatus.isFinal && ($0.departure.best ?? .distantFuture) < horizon }
            .compactMap(payload(for:))
        var body: [String: Any] = ["deviceToken": token, "flights": flights, "liveTokens": liveTokens, "lang": appLanguage]
        // Your own server uses your own FlightAware key (sent only to the server you entered, over HTTPS)
        if FlightAware.hasKey, FlightProvider.current != .aerodatabox { body["flightawareKey"] = FlightAware.apiKey }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(serverToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastStatus = code == 200 ? String(localized: "Verbunden · \(flights.count) Flüge beobachtet") : String(localized: "Fehler \(code): \(String(data: data, encoding: .utf8) ?? "")")
        } catch {
            lastStatus = String(localized: "Server nicht erreichbar")
        }
    }

    /// Sends a test push via the server.
    static func test() async -> String {
        guard isConfigured else { return String(localized: "Server-Adresse und Token eintragen.") }
        guard let token = deviceToken else { return String(localized: "Noch kein Push-Token – Mitteilungen erlauben und App neu öffnen.") }
        await sync()
        guard let url = endpoint("/test") else { return String(localized: "Ungültige Adresse.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(serverToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["deviceToken": token, "lang": appLanguage])
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return String(localized: "Server nicht erreichbar.") }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return String(localized: "Test-Push gesendet – sollte gleich erscheinen.")
        case 401: return String(localized: "Token falsch.")
        case 502: return String(localized: "Server erreicht, aber Apple lehnt den Push ab (APNs-Schlüssel prüfen).")
        default: return String(localized: "Unerwartete Antwort vom Server.")
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushClient.didRegister(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushClient.lastStatus = String(localized: "Push-Registrierung fehlgeschlagen: \(error.localizedDescription)") }
    }
}
