import SwiftUI
import MapKit
import UIKit

/// Builds a printable itinerary PDF (e.g. to send to family).
@MainActor
enum FlightPDF {
    static let pageWidth: CGFloat = 595 // A4 width in points

    static func make(_ unsorted: [Flight]) async -> URL? {
        guard !unsorted.isEmpty else { return nil }
        let flights = unsorted.sorted { $0.sortDate < $1.sortDate }
        var maps: [UUID: UIImage] = [:]
        // maps only for short lists (one snapshot per flight takes time)
        if flights.count <= 10 {
            for f in flights {
                if let img = await snapshot(f) { maps[f.id] = img }
            }
        }

        let name = flights.count == 1 ? "Flug \(flights[0].number) \(flights[0].date)" : "Reiseplan"
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).pdf")
        // One page per few flights instead of a single endless page
        let perPage = maps.isEmpty ? 5 : 2
        let pages = stride(from: 0, to: flights.count, by: perPage).map { Array(flights[$0..<min($0 + perPage, flights.count)]) }
        var a4 = CGRect(x: 0, y: 0, width: pageWidth, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &a4, nil) else { return nil }
        var success = false
        for page in pages {
            let renderer = ImageRenderer(content:
                ItineraryPDFView(flights: page, maps: maps)
                    .frame(width: pageWidth)
                    .environment(\.colorScheme, .light)
            )
            renderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
            renderer.render { size, draw in
                var box = CGRect(origin: .zero, size: CGSize(width: pageWidth, height: max(size.height, 842)))
                let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
                ctx.beginPDFPage(info)
                // content starts at the top of the page
                ctx.translateBy(x: 0, y: box.height - size.height)
                draw(ctx)
                ctx.endPDFPage()
                success = true
            }
        }
        ctx.closePDF()
        return success ? url : nil
    }

    private static func snapshot(_ f: Flight) async -> UIImage? {
        guard let a = f.departure.coordinate, let b = f.arrival.coordinate else { return nil }
        let line = MKGeodesicPolyline(coordinates: [a, b], count: 2)
        let options = MKMapSnapshotter.Options()
        options.mapRect = line.boundingMapRect.insetBy(dx: -line.boundingMapRect.width * 0.25 - 50_000,
                                                       dy: -line.boundingMapRect.height * 0.25 - 50_000)
        options.size = CGSize(width: 520, height: 220)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        options.pointOfInterestFilter = .excludingAll
        guard let snap = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let points = (0..<line.pointCount).map { snap.point(for: line.points()[$0].coordinate) }
        let plane = f.planePosition().map { (snap.point(for: $0.coordinate), $0.heading) }
        return UIGraphicsImageRenderer(size: options.size).image { ctx in
            snap.image.draw(at: .zero)
            let cg = ctx.cgContext
            cg.setStrokeColor(UIColor.systemBlue.cgColor)
            cg.setLineWidth(3)
            cg.setLineDash(phase: 0, lengths: [6, 5])
            cg.addLines(between: points)
            cg.strokePath()
            cg.setLineDash(phase: 0, lengths: [])
            for p in [snap.point(for: a), snap.point(for: b)] {
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
                cg.setStrokeColor(UIColor.systemBlue.cgColor)
                cg.strokeEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
            }
            if let plane, case let (p, heading) = plane,
               let img = UIImage(systemName: "airplane")?.withTintColor(.systemOrange, renderingMode: .alwaysOriginal) {
                cg.saveGState()
                cg.translateBy(x: p.x, y: p.y)
                cg.rotate(by: (heading - 90) * .pi / 180)
                img.draw(in: CGRect(x: -12, y: -12, width: 24, height: 24))
                cg.restoreGState()
            }
        }
    }
}

private struct ItineraryPDFView: View {
    let flights: [Flight]
    let maps: [UUID: UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(flights.count == 1 ? String(localized: "Flugdetails") : String(localized: "Reiseplan")).font(.system(size: 26, weight: .bold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.gray)
                }
                Spacer()
                Image(systemName: "airplane.circle.fill").font(.system(size: 34)).foregroundStyle(.blue)
            }
            ForEach(flights) { f in
                FlightPDFCard(flight: f, map: maps[f.id])
            }
            Text("Alle Zeiten in Ortszeit des jeweiligen Flughafens. Stand: \(Date().formatted(date: .abbreviated, time: .shortened)) · erstellt mit Awaymate")
                .font(.system(size: 9))
                .foregroundStyle(.gray)
        }
        .padding(28)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    private var subtitle: String {
        let codes = flights.map(\.departure.code) + [flights.last?.arrival.code ?? ""]
        return codes.joined(separator: " → ")
    }
}

private struct FlightPDFCard: View {
    let flight: Flight
    let map: UIImage?

    var body: some View {
        let f = flight
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(f.number)\(f.airlineName.map { " · \($0)" } ?? "")").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(f.normalizedStatus.label)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(f.normalizedStatus.color.opacity(0.18), in: Capsule())
            }
            Text(Fmt.day(f.departure.scheduled ?? f.sortDate, f.departure.tz)).font(.system(size: 12)).foregroundStyle(.gray)

            HStack(alignment: .top) {
                endpoint(String(localized: "Abflug"), f.departure, leading: true)
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: "airplane").foregroundStyle(.blue)
                    if let m = f.durationMinutes { Text(Fmt.duration(m)).font(.system(size: 10)).foregroundStyle(.gray) }
                    if let km = f.computedDistanceKm { Text(Fmt.km(km)).font(.system(size: 10)).foregroundStyle(.gray) }
                }
                .padding(.top, 18)
                Spacer()
                endpoint(String(localized: "Ankunft"), f.arrival, leading: false)
            }

            if let map {
                Image(uiImage: map).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
            }

            let extras: [(String, String?)] = [
                (String(localized: "Flugzeug"), f.aircraftModel), (String(localized: "Kennzeichen"), f.aircraftReg),
                (String(localized: "Sitzplatz"), f.seat.isEmpty ? nil : f.seat), (String(localized: "Gepäckband"), f.arrival.baggageBelt),
            ]
            let shown = extras.filter { $0.1 != nil }
            if !shown.isEmpty {
                HStack(spacing: 18) {
                    ForEach(shown, id: \.0) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.0).font(.system(size: 9)).foregroundStyle(.gray)
                            Text(item.1 ?? "").font(.system(size: 12, weight: .medium))
                        }
                    }
                }
            }
            if !f.notes.isEmpty {
                Text(f.notes).font(.system(size: 11)).foregroundStyle(.gray)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.35)))
    }

    private func endpoint(_ title: String, _ e: FlightEndpoint, leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .trailing, spacing: 2) {
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.gray)
            Text(e.code).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(e.name ?? e.displayCity).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(1)
            HStack(spacing: 4) {
                if let d = Fmt.delay(e.delayMinutes) {
                    Text(Fmt.time(e.scheduled, e.tz)).strikethrough().foregroundStyle(.gray).font(.system(size: 11))
                    Text(Fmt.time(e.best, e.tz)).font(.system(size: 18, weight: .semibold))
                    Text(d).font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
                } else {
                    Text(Fmt.time(e.best, e.tz)).font(.system(size: 18, weight: .semibold))
                }
            }
            Text(Fmt.tzAbbrev(e.tz, at: e.best)).font(.system(size: 9)).foregroundStyle(.gray)
            let gate = [e.terminal.map { String(localized: "Terminal \($0)") }, e.gate.map { String(localized: "Gate \($0)") }].compactMap { $0 }
            if !gate.isEmpty { Text(gate.joined(separator: " · ")).font(.system(size: 11, weight: .medium)) }
        }
    }
}

/// UIKit share sheet (for files generated on demand).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
