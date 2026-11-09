import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct SkylogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = FlightStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationDelegate.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .task {
                    await Notifier.requestAuthorization()
                    PushClient.register()
                    LiveFlight.observeExistingTokens()
                    TravelMode.shared.evaluate(store)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                BackgroundRefresh.schedule()
            case .active:
                Task {
                    await store.refreshActive()
                    TravelMode.shared.evaluate(store)
                    await MailWatcher.check(store: store)
                }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            BackgroundRefresh.schedule()
            await FlightStore.shared.refreshActive(notify: true)
            await MailWatcher.check(store: FlightStore.shared)
            await TravelMode.shared.evaluate(FlightStore.shared)
        }
    }
}

enum BackgroundRefresh {
    static let identifier = "com.nobody430.skylog.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(20 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

struct ImportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct RootView: View {
    @State private var importFile: ImportFile?

    var body: some View {
        TabView {
            FlightListView()
                .tabItem { Label("Flüge", systemImage: "airplane") }
            TripsView()
                .tabItem { Label("Reisen", systemImage: "suitcase") }
            AllFlightsMapView()
                .tabItem { Label("Karte", systemImage: "map") }
            StatsView()
                .tabItem { Label("Statistik", systemImage: "chart.bar.xaxis") }
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .onOpenURL { url in
            if url.isFileURL { importFile = ImportFile(url: url) }
        }
        .sheet(item: $importFile) { file in
            ImportView(initialFile: file.url)
        }
    }
}
