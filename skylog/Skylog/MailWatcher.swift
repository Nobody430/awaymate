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

    /// Shown in the settings so a silently failing watcher is noticed.
    static var lastError: String? { UserDefaults.standard.string(forKey: "mailWatchError") }
    private static func seenFailure(_ e: Error) {
        UserDefaults.standard.set("\(Date().formatted(date: .abbreviated, time: .shortened)): \(e.localizedDescription)", forKey: "mailWatchError")
    }

    static func check(store: FlightStore, force: Bool = false) async {
        guard enabled, OutlookAuth.shared.isConnected, !running else { return }
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < 20 * 60 { return }
        running = true
        defer { running = false }

        let since = (lastCheck ?? Date().addingTimeInterval(-7 * 86400)).addingTimeInterval(-10 * 60)
        do {
            let started = Date()
            let mails = try await OutlookMail.recentMails(since: since)
            // Don't send the same mail to the AI twice (overlap window, repeated checks)
            var seen = Set(UserDefaults.standard.stringArray(forKey: "processedMailIDs") ?? [])
            let relevant = MailAI.relevant(mails).filter { !seen.contains($0.id) }
            guard !relevant.isEmpty else { lastCheck = started; return }
            // lastCheck and the processed list only move forward once the mails were really read (below)
            func markProcessed() {
                lastCheck = started
                seen.formUnion(relevant.map(\.id))
                let ordered = (UserDefaults.standard.stringArray(forKey: "processedMailIDs") ?? []) + relevant.map(\.id)
                UserDefaults.standard.set(Array(ordered.suffix(500)), forKey: "processedMailIDs")
                UserDefaults.standard.removeObject(forKey: "mailWatchError")
            }

            var candidates: [FlightCandidate]
            if AIClient.hasKey {
                let result = try await MailAI.extractAll(relevant) { _ in }
                guard result.failedMails == 0 else { throw AIClient.Failure(message: result.failure ?? String(localized: "KI-Fehler")) }
                markProcessed()
                candidates = result.flights
                for b in result.bookings where BookingStore.shared.upsert(b) {
                    let title = b.cancelled ? String(localized: "\(b.kind.label) storniert") : String(localized: "Neue Buchung: \(b.kind.label)")
                    Notifier.post(id: "mail-booking-\(b.key)", title: title,
                                  body: "\(b.name), \(b.city) · \(Fmt.day(b.start))" + (b.kind == .hotel && b.nights > 0 ? String(localized: " · \(b.nights) Nächte") : ""))
                }
            } else {
                candidates = relevant.flatMap { m in
                    FlightTextParser.parse(m.subject + "\n" + m.text, source: m.subject, reference: m.received)
                }
                .filter(ImportView.isPlausible)
                markProcessed()
            }

            let stillBooked = Set(candidates.filter { !$0.cancelled }.map {
                FlightStore.normalizedNumber($0.number) + "|" + Fmt.apiDate.string(from: $0.date) })
            for c in candidates {
                if c.cancelled {
                    if var existing = store.flights.first(where: {
                        FlightStore.normalizedNumber($0.number) == FlightStore.normalizedNumber(c.number) && $0.date == Fmt.apiDate.string(from: c.date) }),
                       existing.normalizedStatus != .canceled {
                        existing.status = "Canceled"
                        store.update(existing)
                        Notifier.post(id: "mail-cancel-\(c.id)", title: String(localized: "✈️ \(c.number) storniert"),
                                      body: String(localized: "Laut einer neuen Mail wurde dein Flug am \(Fmt.day(c.date)) storniert."))
                    }
                    continue
                }
                guard !store.contains(number: c.number, date: c.date),
                      var flight = await ImportView.manualFlight(c) else { continue }
                let route = String(localized: "\(flight.number) \(flight.departure.displayCity) → \(flight.arrival.displayCity) am \(Fmt.day(c.date))")
                // Re-booking: same booking code, the old flight is no longer in the mail
                if let old = store.rebookedFlight(for: flight, stillBooked: stillBooked) {
                    let what = String(localized: "\(old.number) am \(Fmt.day(old.sortDate, old.departure.tz)) wurde umgebucht auf \(route)")
                    if autoAdd {
                        store.delete([old.id])
                        store.add(flight)
                        Notifier.post(id: "mail-rebook-\(c.id)", title: String(localized: "✈️ Flug umgebucht"), body: what + String(localized: ". In Skylog ersetzt."))
                    } else {
                        flight.replacesID = old.id
                        if store.suggest(flight) {
                            Notifier.post(id: "mail-rebook-\(c.id)", title: String(localized: "✈️ Flug umgebucht?"), body: what + String(localized: ". Ersetzen?"),
                                          category: NotificationDelegate.newFlightCategory,
                                          userInfo: ["pendingID": flight.id.uuidString])
                        }
                    }
                    continue
                }
                if autoAdd {
                    store.add(flight)
                    Notifier.post(id: "mail-new-\(c.id)", title: String(localized: "✈️ Neuer Flug hinzugefügt"), body: route + ".")
                } else if store.suggest(flight) {
                    Notifier.post(id: "mail-new-\(c.id)", title: String(localized: "✈️ Neuer Flug in deinen Mails"),
                                  body: route + String(localized: ". Hinzufügen?"),
                                  category: NotificationDelegate.newFlightCategory,
                                  userInfo: ["pendingID": flight.id.uuidString])
                }
            }
        } catch {
            // Silent in the background; the next check tries again (lastCheck was not moved).
            seenFailure(error)
        }
    }
}
