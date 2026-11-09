import SwiftUI

struct FlightDetailView: View {
    @Environment(FlightStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let flightID: UUID

    @State private var refreshing = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var sharedPDF: SharedFile?

    var body: some View {
        if let flight = store.flight(flightID) {
            content(flight)
        } else {
            ContentUnavailableView("Flug nicht gefunden", systemImage: "airplane")
        }
    }

    private func content(_ f: Flight) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                FlightRouteMap(flight: f)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                header(f)
                LiveActivityButton(flight: f)
                times(f)
                gates(f)
                if let i = f.inbound, !f.isInAir, !f.normalizedStatus.isFinal { inbound(i, f) }
                if f.isInAir, let p = f.lastPosition { live(p) }
                if f.isPast || f.normalizedStatus.isFinal || (f.arrival.delayMinutes ?? 0) >= 120 {
                    CompensationCard(flight: f)
                }
                TravelDayCard(flight: f)
                TransitCard(flight: f)
                HotelRouteCard(flight: f)
                DestinationCard(flight: f)
                FamilyCard(flight: f)
                AircraftSeatCard(flight: f)
                if !f.isPast {
                    AirportCard(endpoint: f.departure, title: "Abflug")
                }
                AirportCard(endpoint: f.arrival, title: "Ankunft")
                DocumentsCard(flightID: f.id)
                aircraft(f)
                personal

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
                if let updated = f.lastUpdated {
                    Text("Aktualisiert \(updated.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(f.number)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if refreshing { ProgressView() }
                Menu {
                    Button {
                        Task { if let url = await FlightPDF.make([f]) { sharedPDF = SharedFile(url: url) } }
                    } label: {
                        Label("Als PDF teilen", systemImage: "doc.richtext")
                    }
                    ShareLink(item: Fmt.shareText(f)) { Label("Als Text teilen", systemImage: "text.bubble") }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                Menu {
                    Button { Task { await refresh() } } label: {
                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Flug löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Flug löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                dismiss()
                store.delete([flightID])
            }
        }
        .refreshable { await refresh() }
        .sheet(item: $sharedPDF) { file in
            ShareSheet(items: [file.url]).presentationDetents([.medium, .large])
        }
        .task(id: flightID) {
            if let current = store.flight(flightID), !current.isPast,
               current.lastUpdated.map({ Date().timeIntervalSince($0) > 20 * 60 }) ?? true {
                await refresh()
            }
            while !Task.isCancelled {
                await store.updateLive(flightID)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        do {
            try await store.refresh(flightID)
            await store.updateLive(flightID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Sections

    private func header(_ f: Flight) -> some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text(f.airlineName ?? f.number).font(.headline)
                    Text(Fmt.day(f.departure.scheduled ?? f.sortDate, f.departure.tz))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(flight: f)
            }
            HStack {
                VStack(alignment: .leading) {
                    Text(f.departure.code).font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(f.departure.displayCity).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack {
                    Image(systemName: "airplane").font(.title3).foregroundStyle(Theme.accent)
                    if let m = f.durationMinutes { Text(Fmt.duration(m)).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(f.arrival.code).font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(f.arrival.displayCity).font(.caption).foregroundStyle(.secondary)
                }
            }
            if f.isInAir || f.normalizedStatus == .arrived {
                FlightProgressBar(progress: f.progress())
            }
            Text(Fmt.summary(f)).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func times(_ f: Flight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            timeColumn("Abflug", f.departure, actual: f.departure.runway != nil)
            timeColumn("Ankunft", f.arrival, actual: f.arrival.runway != nil)
        }
    }

    private func timeColumn(_ title: String, _ e: FlightEndpoint, actual: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TimeLabel(endpoint: e, font: .title.weight(.bold))
            Text("Geplant \(Fmt.time(e.scheduled, e.tz)) \(Fmt.tzAbbrev(e.tz, at: e.scheduled))")
                .font(.caption).foregroundStyle(.secondary)
            if let d = Fmt.delay(e.delayMinutes) {
                Text(d).font(.caption.weight(.semibold)).foregroundStyle(Fmt.delayColor(e.delayMinutes))
            } else if e.scheduled != nil {
                Text("Pünktlich").font(.caption.weight(.semibold)).foregroundStyle(.green)
            }
            Text(actual ? "Tatsächlich" : (e.revised ?? e.predicted) != nil ? "Erwartet" : "Planzeit")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func gates(_ f: Flight) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Abflug · \(f.departure.name ?? f.departure.code)").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                InfoTile(title: "Terminal", value: f.departure.terminal)
                InfoTile(title: "Gate", value: f.departure.gate)
                InfoTile(title: "Check-in", value: f.departure.checkInDesk)
            }
            Text("Ankunft · \(f.arrival.name ?? f.arrival.code)").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            LazyVGrid(columns: columns, spacing: 8) {
                InfoTile(title: "Terminal", value: f.arrival.terminal)
                InfoTile(title: "Gate", value: f.arrival.gate)
                InfoTile(title: "Gepäck", value: f.arrival.baggageBelt, icon: "suitcase.rolling")
            }
        }
    }

    private func inbound(_ i: InboundFlight, _ f: Flight) -> some View {
        let delay = i.expectedDelay(ourDeparture: f.departure.best)
        let color: Color = i.isCanceled ? .red : delay >= 15 ? .orange : i.landed ? .green : Theme.accent
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: i.landed ? "airplane.arrival" : i.departed ? "airplane" : "airplane.departure")
                    .foregroundStyle(color)
                Text("Dein Flugzeug").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("vor \(Fmt.countdown(Date().timeIntervalSince(i.updated)))").font(.caption2).foregroundStyle(.secondary)
            }
            Text(i.headline).font(.headline).foregroundStyle(color)
            Text(i.detail(tz: f.departure.tz)).font(.subheadline)
            if delay >= 15 {
                Text("Abflug voraussichtlich ca. \(delay) Min. später (inkl. \(Int(InboundFlight.turnaround / 60)) Min. Bodenzeit)")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func live(_ p: LivePosition) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("Live · \(p.source) · \(p.timestamp.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                InfoTile(title: "Höhe", value: p.altitudeM.map { "\(Int($0 * 3.28084).formatted()) ft" }, icon: "arrow.up.to.line")
                InfoTile(title: "Geschwindigkeit", value: p.speedKmh.map { "\(Int($0)) km/h" }, icon: "speedometer")
                InfoTile(title: "Kurs", value: p.heading.map { "\(Int($0))°" }, icon: "location.north.line")
                InfoTile(title: "Steigrate", value: p.verticalRate.map { "\(Int($0 * 196.85)) ft/min" }, icon: "arrow.up.right")
            }
        }
    }

    private func aircraft(_ f: Flight) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            row("Flugzeug", f.aircraftModel)
            row("Kennzeichen", f.aircraftReg)
            row("Rufzeichen", f.callSign)
            row("Transponder", f.icao24?.uppercased())
            row("Distanz", f.computedDistanceKm.map(Fmt.km))
            row("Airline", [f.airlineName, f.airlineIata].compactMap { $0 }.joined(separator: " · "))
        }
        .padding(.horizontal)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text((value?.isEmpty ?? true) ? "–" : value!).fontWeight(.medium)
        }
        .font(.subheadline)
        .padding(.vertical, 10)
    }

    private var personal: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Persönlich").font(.caption).foregroundStyle(.secondary)
            TextField("Sitzplatz", text: binding(\.seat))
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            TextField("Notizen (Buchungscode, Lounge …)", text: binding(\.notes), axis: .vertical)
                .lineLimit(2...6)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func binding(_ keyPath: WritableKeyPath<Flight, String>) -> Binding<String> {
        Binding(
            get: { store.flight(flightID)?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var f = store.flight(flightID) else { return }
                f[keyPath: keyPath] = value
                store.update(f)
            }
        )
    }
}
