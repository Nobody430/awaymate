import WidgetKit
import SwiftUI
import ActivityKit

@main
struct SkylogWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextFlightWidget()
        FlightLiveActivity()
    }
}

private let accent = Color(red: 0.36, green: 0.62, blue: 1.0)

// MARK: - Home screen widget

struct NextFlightEntry: TimelineEntry {
    let date: Date
    let flight: WidgetFlight?
}

struct NextFlightProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextFlightEntry {
        NextFlightEntry(date: .now, flight: WidgetFlight(id: "x", number: "LX 1612", from: "ZRH", to: "LIS", fromCity: "Zürich",
                                                        toCity: "Lissabon", departure: .now.addingTimeInterval(7200),
                                                        arrival: .now.addingTimeInterval(18000), gate: "E42", terminal: "2",
                                                        status: String(localized: "Planmässig"), delayMinutes: 0))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextFlightEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextFlightEntry>) -> Void) {
        // One entry per phase change, so the widget switches at departure and moves on after landing
        let now = Date()
        var entries = [entry(at: now)]
        if let f = entries[0].flight {
            for d in [f.departure, f.arrival.addingTimeInterval(30 * 60)] where d > now { entries.append(entry(at: d.addingTimeInterval(1))) }
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }

    private func entry(at date: Date = .now) -> NextFlightEntry {
        let next = SharedStore.read().filter { $0.arrival.addingTimeInterval(30 * 60) > date }.sorted { $0.departure < $1.departure }.first
        return NextFlightEntry(date: date, flight: next)
    }
}

struct NextFlightView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextFlightEntry

    var body: some View {
        if family == .accessoryInline {
            // one line above the clock
            if let f = entry.flight {
                let line = " \(f.number) \(f.from)→\(f.to) \(f.departure.formatted(date: .omitted, time: .shortened))" + (f.gate.map { " · \($0)" } ?? "")
                Text(Image(systemName: "airplane")) + Text(line)
            } else {
                Text(Image(systemName: "airplane")) + Text(" Kein Flug geplant")
            }
        } else if family == .accessoryRectangular {
            // compact block under the clock
            if let f = entry.flight {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(f.number) · \(f.from) → \(f.to)").font(.headline).lineLimit(1)
                    if f.departure > entry.date {
                        Text("Abflug \(f.departure, style: .relative)").font(.caption).lineLimit(1)
                    } else {
                        Text("Landung \(f.arrival.formatted(date: .omitted, time: .shortened))").font(.caption)
                    }
                    Text([f.delayMinutes >= 5 ? String(localized: "+\(f.delayMinutes) Min") : f.status, f.terminal.map { String(localized: "T\($0)") }, f.gate.map { String(localized: "Gate \($0)") }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerBackground(for: .widget) { Color.clear }
            } else {
                Text("Kein Flug geplant").font(.caption)
                    .containerBackground(for: .widget) { Color.clear }
            }
        } else if let f = entry.flight {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(f.number).font(.caption.weight(.semibold))
                    Spacer()
                    Text(f.delayMinutes >= 5 ? String(localized: "+\(f.delayMinutes) Min") : f.status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(f.delayMinutes >= 15 ? .red : f.delayMinutes >= 5 ? .orange : accent)
                }
                HStack {
                    Text(f.from).font(.title2.bold())
                    Image(systemName: "airplane").font(.caption).foregroundStyle(.secondary)
                    Text(f.to).font(.title2.bold())
                }
                if f.departure > .now {
                    Text("Abflug in").font(.caption2).foregroundStyle(.secondary)
                    Text(f.departure, style: .relative).font(.headline.monospacedDigit())
                } else {
                    Text("Landung").font(.caption2).foregroundStyle(.secondary)
                    ProgressView(timerInterval: f.departure...max(f.departure.addingTimeInterval(60), f.arrival), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(accent)
                }
                if family != .systemSmall {
                    HStack {
                        Text("\(f.departure.formatted(date: .abbreviated, time: .shortened))")
                        Spacer()
                        if let t = f.terminal { Text("T\(t)") }
                        if let g = f.gate { Text("Gate \(g)").bold() }
                    }
                    .font(.caption)
                }
            }
            .containerBackground(for: .widget) { Color.black }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "airplane").font(.title)
                Text("Keine anstehenden Flüge").font(.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .containerBackground(for: .widget) { Color.black }
        }
    }
}

struct NextFlightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextFlight", provider: NextFlightProvider()) { entry in
            NextFlightView(entry: entry)
        }
        .configurationDisplayName("Nächster Flug")
        .description("Countdown, Gate und Status deines nächsten Flugs.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Live Activity

struct FlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            LockScreenFlightView(context: context)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(context.attributes.from).font(.title2.bold())
                        Text(airportTime(context.state.departure, context.attributes.fromTZ)).font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text(context.attributes.to).font(.title2.bold())
                        Text(airportTime(context.state.arrival, context.attributes.toTZ)).font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.flightNumber).font(.caption.bold())
                        let late = context.state.delayMinutes >= 5 && !context.state.inAir && !context.state.isLanded
                        Text(late ? String(localized: "+\(context.state.delayMinutes) Min") : context.state.status)
                            .font(.caption2).foregroundStyle(late ? .orange : accent)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FlightProgressRow(state: context.state)
                }
            } compactLeading: {
                HStack(spacing: 2) {
                    Image(systemName: "airplane").foregroundStyle(accent)
                    Text(context.attributes.to).font(.caption.bold())
                }
            } compactTrailing: {
                Countdown(target: context.state.inAir || context.state.departure < Date() ? context.state.arrival : context.state.departure,
                          overdue: context.state.isLanded ? "✓" : String(localized: "jetzt"))
                    .monospacedDigit()
                    .frame(maxWidth: 52)
                    .font(.caption)
            } minimal: {
                Image(systemName: "airplane").foregroundStyle(accent)
            }
        }
    }
}

struct LockScreenFlightView: View {
    let context: ActivityViewContext<FlightActivityAttributes>

    var body: some View {
        let s = context.state
        VStack(spacing: 8) {
            HStack {
                Text(context.attributes.flightNumber).font(.subheadline.bold())
                Spacer()
                let showDelay = s.delayMinutes >= 5 && !s.inAir && !s.isLanded
                Text(showDelay ? String(localized: "Verspätet · +\(s.delayMinutes) Min") : s.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(!showDelay ? (s.isLanded ? .green : accent) : s.delayMinutes >= 15 ? .red : .orange)
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.attributes.from).font(.title.bold())
                    Text(airportTime(s.departure, context.attributes.fromTZ))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(delayColor(s.delayMinutes))
                    Text(delayText(s.delayMinutes)).font(.caption2).foregroundStyle(delayColor(s.delayMinutes))
                }
                Spacer()
                VStack {
                    let now = Date()
                    let landed = s.isLanded
                    if landed {
                        Text("Gelandet").font(.caption2).foregroundStyle(.secondary)
                        Text(airportTime(s.arrival, context.attributes.toTZ)).font(.headline)
                    } else if s.departure > now && !s.inAir {
                        Text("Abflug in").font(.caption2).foregroundStyle(.secondary)
                        Countdown(target: s.departure, overdue: String(localized: "jetzt")).font(.headline.monospacedDigit())
                    } else if s.arrival > now {
                        // departed (or departure time passed without newer data): count down to landing
                        Text("Landung in").font(.caption2).foregroundStyle(.secondary)
                        Countdown(target: s.arrival, overdue: String(localized: "jetzt")).font(.headline.monospacedDigit())
                    } else {
                        Text("Ankunft").font(.caption2).foregroundStyle(.secondary)
                        Text(airportTime(s.arrival, context.attributes.toTZ)).font(.headline)
                    }
                }
                .multilineTextAlignment(.center)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(context.attributes.to).font(.title.bold())
                    Text(airportTime(s.arrival, context.attributes.toTZ))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(s.arrivalDelay.map(delayColor) ?? .white)
                    if let d = s.arrivalDelay {
                        Text(delayText(d)).font(.caption2).foregroundStyle(delayColor(d))
                    }
                }
            }
            FlightProgressRow(state: s)
            if let line = s.inbound {
                HStack(spacing: 6) {
                    Image(systemName: "airplane.arrival")
                    Text(line).lineLimit(1)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(s.inboundWarn == true ? .orange : .secondary)
            }
        }
        .foregroundStyle(.white)
    }
}

/// "Pünktlich" / "49 Min. später" / "16 Min. früher"
func delayText(_ minutes: Int) -> String {
    if minutes >= 5 { return String(localized: "\(minutes) Min. später") }
    if minutes <= -5 { return String(localized: "\(-minutes) Min. früher") }
    return String(localized: "Pünktlich")
}

extension FlightActivityAttributes.ContentState {
    /// Landed flag; falls back to the German status label because a server may still send only that.
    var isLanded: Bool { landed ?? (status == "Gelandet") }
}

func delayColor(_ minutes: Int) -> Color {
    minutes >= 15 ? .red : minutes >= 5 ? .orange : .green
}

struct FlightProgressRow: View {
    let state: FlightActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 4) {
            if state.inAir {
                ProgressView(timerInterval: state.departure...max(state.departure.addingTimeInterval(60), state.arrival), countsDown: false) {
                    EmptyView()
                } currentValueLabel: { EmptyView() }
                .tint(accent)
            }
            HStack {
                if let t = state.terminal { Text("Terminal \(t)") }
                if let g = state.gate { Text("Gate \(g)").bold() }
                Spacer()
                // airlines publish early guesses – show the belt only once airborne / landed
                if let b = state.belt, state.inAir || state.isLanded { Label("Band \(b)", systemImage: "suitcase.rolling") }
            }
            .font(.caption)
        }
    }
}

/// Countdown that never builds an invalid time range (a past target crashed the Live Activity).
struct Countdown: View {
    let target: Date
    var overdue: String

    var body: some View {
        let now = Date()
        if target > now {
            Text(timerInterval: now...target, countsDown: true)
        } else {
            Text(overdue)
        }
    }
}
