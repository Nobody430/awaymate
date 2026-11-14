import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct SkylogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = FlightStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // after a reinstall: keys and settings come back from the keychain before anything reads them
        SettingsBackup.restoreIfNeeded()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationDelegate.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .task {
                    SettingsBackup.save()
                    await Notifier.requestAuthorization()
                    PushClient.register()
                    LiveFlight.observeExistingTokens()
                    TravelMode.shared.evaluate(store)
                    BackgroundRefresh.schedule()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                BackgroundRefresh.schedule()
                SettingsBackup.save()
                Task { await DeviceSync.sync() }
            case .active:
                Task {
                    await DeviceSync.sync()
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
            // flights first – the background budget is only ~30 s
            await TravelMode.shared.evaluate(FlightStore.shared)
            await FlightStore.shared.refreshActive(notify: true)
            await MailWatcher.check(store: FlightStore.shared)
        }
    }
}

enum BackgroundRefresh {
    static let identifier = "com.nobody430.skylog.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

struct ImportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct RootView: View {
    @State private var importFile: ImportFile?
    @State private var attachFile: ImportFile?

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
            guard url.isFileURL else { return }
            // PDFs, images and Wallet passes are documents for a flight; everything else goes to the import
            if ["pdf", "png", "jpg", "jpeg", "heic", "pkpass"].contains(url.pathExtension.lowercased()) {
                attachFile = ImportFile(url: url)
            } else {
                importFile = ImportFile(url: url)
            }
        }
        .sheet(item: $importFile) { file in
            ImportView(initialFile: file.url)
        }
        .sheet(item: $attachFile) { file in
            AttachDocumentView(url: file.url) {
                // let the first sheet close before the import opens
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { importFile = ImportFile(url: file.url) }
            }
        }
    }
}
