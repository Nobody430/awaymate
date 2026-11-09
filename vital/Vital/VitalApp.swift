import SwiftUI
import UserNotifications
import LocalAuthentication

@main
struct VitalApp: App {
    @State private var training = TrainingStore.shared
    @State private var weight = WeightStore.shared
    @State private var prep = PrepStore.shared
    @State private var nutrition = NutritionStore.shared

    init() {
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
        NotificationHandler.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            LockGate {
                RootView()
            }
            .environment(training)
            .environment(weight)
            .environment(prep)
            .environment(nutrition)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                prep.rescheduleReminders()
            }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TrainingHomeView()
                .tabItem { Label("Training", systemImage: "dumbbell") }
            NutritionView()
                .tabItem { Label("Essen", systemImage: "fork.knife") }
            WeightView()
                .tabItem { Label("Gewicht", systemImage: "scalemass") }
            PrepView()
                .tabItem { Label("PrEP", systemImage: "pills") }
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.2, green: 0.85, blue: 0.62)
    static let card = Color(white: 0.12)
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
    var icon: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - App lock (Face ID)

struct LockGate<Content: View>: View {
    @ViewBuilder var content: Content
    @AppStorage("lockEnabled") private var lockEnabled = false
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
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Vital entsperren") { ok, _ in
            DispatchQueue.main.async { unlocked = ok }
        }
    }
}

// MARK: - Notifications

final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()
    static let doseCategory = "DOSE"
    static let takenAction = "TAKEN"

    static func registerCategories() {
        let taken = UNNotificationAction(identifier: takenAction, title: "Genommen ✓", options: [])
        let category = UNNotificationCategory(identifier: doseCategory, actions: [taken], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == Self.takenAction {
            DispatchQueue.main.async {
                PrepStore.shared.logDose()
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
}

// MARK: - Persistence

enum Disk {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

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

extension Double {
    var clean: String {
        formatted(.number.precision(.fractionLength(0...1)))
    }
}
