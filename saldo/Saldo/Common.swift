import SwiftUI
import LocalAuthentication
import Security

enum Theme {
    static let accent = Color(red: 0.27, green: 0.86, blue: 0.63)
    static let card = Color(white: 0.12)
    static let negative = Color(red: 1.0, green: 0.42, blue: 0.42)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

enum Money {
    static func chf(_ v: Double, decimals: Int = 2) -> String {
        "CHF " + v.formatted(.number.precision(.fractionLength(decimals)).grouping(.automatic).locale(Locale(identifier: "de_CH")))
    }
    static func short(_ v: Double) -> String {
        abs(v) >= 10_000 ? chf(v, decimals: 0) : chf(v)
    }
}

struct LockGate<Content: View>: View {
    @ViewBuilder var content: Content
    @AppStorage("lockEnabled") private var lockEnabled = true
    @Environment(\.scenePhase) private var phase
    @State private var unlocked = false

    var body: some View {
        ZStack {
            content
            if lockEnabled && !unlocked {
                Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill").font(.largeTitle)
                    Button("Entsperren") { authenticate() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear { if lockEnabled { authenticate() } }
        .onChange(of: phase) { _, p in
            if p == .background { unlocked = false }
            if p == .active && lockEnabled && !unlocked { authenticate() }
        }
    }

    private func authenticate() {
        LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Saldo entsperren") { ok, _ in
            DispatchQueue.main.async { unlocked = ok }
        }
    }
}

enum Disk {
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    static func url(_ name: String) -> URL { URL.documentsDirectory.appending(path: name) }
    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? decoder.decode(type, from: data)
    }
    static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: [.atomic, .completeFileProtection])
    }
}

enum Keychain {
    private static let service = "com.nobody430.saldo"
    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
