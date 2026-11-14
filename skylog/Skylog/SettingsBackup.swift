import Foundation

/// Keeps the keys and settings in the keychain as well. The keychain survives deleting the app, the normal
/// settings do not – so after a reinstall the keys are back without typing them in again.
enum SettingsBackup {
    private static let account = "settingsBackup"
    private static let strings = ["apiKey", "flightawareKey", "anthropicKey", "openaiKey", "openaiModel", "aiProvider", "provider",
                                  "outlookClientID", "passengerName", "pushServerURL", "pushServerToken", "homeStation", "homeAirport"]
    private static let flags = ["autoRefresh", "notifyChanges", "reminders", "liveActivities", "mailWatch", "mailAutoAdd",
                                "travelMode", "deviceSync"]

    /// Writes the current settings to the keychain (only when something changed).
    static func save() {
        let d = UserDefaults.standard
        var out: [String: Any] = [:]
        for k in strings { if let v = d.string(forKey: k), !v.isEmpty { out[k] = v } }
        for k in flags { if let v = d.object(forKey: k) as? Bool { out[k] = v } }
        // never overwrite a good backup with an empty one (e.g. right after a reinstall, before the restore)
        guard out["apiKey"] != nil || out["flightawareKey"] != nil || out["pushServerToken"] != nil,
              let data = try? JSONSerialization.data(withJSONObject: out, options: .sortedKeys),
              let text = String(data: data, encoding: .utf8), text != Keychain.get(account) else { return }
        Keychain.set(text, for: account)
    }

    /// After a reinstall: no keys in the settings, but a backup in the keychain → bring everything back.
    /// Returns true when settings were restored.
    @discardableResult
    static func restoreIfNeeded() -> Bool {
        let d = UserDefaults.standard
        let empty = ["apiKey", "flightawareKey", "pushServerToken", "anthropicKey", "openaiKey"].allSatisfy { (d.string(forKey: $0) ?? "").isEmpty }
        guard empty, let text = Keychain.get(account), let data = text.data(using: .utf8),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any], !saved.isEmpty else { return false }
        for (k, v) in saved where strings.contains(k) || flags.contains(k) { d.set(v, forKey: k) }
        return true
    }
}
