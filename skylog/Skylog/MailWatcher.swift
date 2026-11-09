import Foundation

/// Periodically checks new mails for flight bookings, changes and cancellations.
@MainActor
enum MailWatcher {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "mailWatch") as? Bool ?? true }
    static var autoAdd: Bool { UserDefaults.standard.bool(forKey: "mailAutoAdd") }

    private static var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: "lastMailCheck") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastMailCheck") }
    }

    private static var running = false

    static func check(store: FlightStore, force: Bool = false) async {
        guard enabled, OutlookAuth.shared.isConnected, !running else { return }
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < 20 * 60 { return }
        running = true
        defer { running = false }

        let since = (lastCheck ?? Date().addingTimeInterval(-7 * 86400)).addingTimeInterval(-10 * 60)
        do {
            let mails = try await OutlookMail.recentMails(since: since)
            lastCheck = Date()
            let relevant = MailAI.relevant(mails)
            guard !relevant.isEmpty else { return }

            var candidates: [FlightCandidate]
            if AIClient.hasKey {
                candidates = try await MailAI.extract(relevant) { _ in }
            } else {
                candidates = relevant.flatMap { m in
                    FlightTextParser.parse(m.subject + "\n" + m.text, source: m.subject, reference: m.received)
                }
                .filter(ImportView.isPlausible)
            }

            for c in candidates {
                if c.cancelled {
                    if var existing = store.flights.first(where: { $0.number == c.number && $0.date == Fmt.apiDate.string(from: c.date) }),
                       existing.normalizedStatus != .canceled {
                        existing.status = "Canceled"
                        store.update(existing)
                        Notifier.post(id: "mail-cancel-\(c.id)", title: "✈️ \(c.number) storniert",
                                      body: "Laut einer neuen Mail wurde dein Flug am \(Fmt.day(c.date)) storniert.")
                    }
                    continue
                }
                guard !store.contains(number: c.number, date: c.date),
                      let flight = await ImportView.manualFlight(c) else { continue }
                let route = "\(flight.number) \(flight.departure.displayCity) → \(flight.arrival.displayCity) am \(Fmt.day(c.date))"
                if autoAdd {
                    store.add(flight)
                    Notifier.post(id: "mail-new-\(c.id)", title: "✈️ Neuer Flug hinzugefügt", body: route + ".")
                } else if store.suggest(flight) {
                    Notifier.post(id: "mail-new-\(c.id)", title: "✈️ Neuer Flug in deinen Mails",
                                  body: route + ". Hinzufügen?",
                                  category: NotificationDelegate.newFlightCategory,
                                  userInfo: ["pendingID": flight.id.uuidString])
                }
            }
        } catch {
            // Silent in the background; the next check tries again.
        }
    }
}
